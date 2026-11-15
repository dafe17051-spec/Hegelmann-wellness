-- FC Hegelmann · Wellness y RPE
-- Las tablas no son accesibles desde fuera: todo pasa por funciones que validan un código.

create table if not exists players(
  id uuid primary key default gen_random_uuid(),
  name text not null, num int, pos text,
  status text not null default 'ok', note text not null default '',
  code text not null unique, created_at timestamptz not null default now());
create table if not exists wellness(
  player_id uuid not null references players(id) on delete cascade, date date not null,
  s int not null check (s between 1 and 10), f int not null check (f between 1 and 10),
  d int not null check (d between 1 and 10), e int not null check (e between 1 and 10),
  a int not null check (a between 1 and 10),
  h numeric, zona text[] not null default '{}', c text not null default '',
  t timestamptz not null default now(), primary key(player_id,date));
create table if not exists rpe(
  player_id uuid not null references players(id) on delete cascade, date date not null,
  tipo text not null, min int not null check (min between 1 and 400),
  rpe int not null check (rpe between 1 and 10),
  t timestamptz not null default now(), primary key(player_id,date,tipo));
create table if not exists messages(
  id bigint generated always as identity primary key,
  player_id uuid references players(id) on delete cascade, -- null = aviso a todo el equipo
  from_staff boolean not null, body text not null, t timestamptz not null default now());
create table if not exists reads(
  player_id uuid primary key references players(id) on delete cascade,
  staff_read timestamptz not null default 'epoch', player_read timestamptz not null default 'epoch');
create table if not exists config(key text primary key, value text not null);

alter table players enable row level security;
alter table wellness enable row level security;
alter table rpe enable row level security;
alter table messages enable row level security;
alter table reads enable row level security;
alter table config enable row level security;

create or replace function _ms(ts timestamptz) returns bigint language sql immutable as
$$ select (extract(epoch from ts)*1000)::bigint $$;

create or replace function _pid(p_code text) returns uuid language plpgsql stable security definer set search_path=public as $$
declare v uuid; begin
  select id into v from players where code=upper(trim(p_code)) and status<>'baja';
  if v is null then raise exception 'no autorizado'; end if; return v; end $$;

create or replace function _staff(p_code text) returns void language plpgsql stable security definer set search_path=public as $$
begin
  if not exists(select 1 from config where key='staff_code' and value=trim(p_code)) then raise exception 'no autorizado'; end if; end $$;

create or replace function _newcode() returns text language plpgsql volatile security definer set search_path=public as $$
declare al text:='ABCDEFGHJKMNPQRSTUVWXYZ23456789'; v text; i int; begin
  loop v:=''; for i in 1..6 loop v:=v||substr(al,1+floor(random()*length(al))::int,1); end loop;
    exit when not exists(select 1 from players where code=v); end loop; return v; end $$;

revoke all on function _pid(text), _staff(text), _newcode() from public, anon, authenticated;

create or replace function login(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare v players; begin
  if exists(select 1 from config where key='staff_code' and value=trim(p_code)) then return jsonb_build_object('role','staff'); end if;
  select * into v from players where code=upper(trim(p_code)) and status<>'baja';
  if v.id is null then perform pg_sleep(0.4); return jsonb_build_object('role',null); end if;
  return jsonb_build_object('role','player','name',v.name); end $$;

create or replace function player_state(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare v uuid:=_pid(p_code); begin
  return jsonb_build_object(
   'player',(select jsonb_build_object('id',id,'name',name,'num',num,'pos',pos,'status',status) from players where id=v),
   'wellness',coalesce((select jsonb_agg(jsonb_build_object('date',date,'s',s,'f',f,'d',d,'e',e,'a',a,'h',h,'zona',zona,'c',c)) from wellness where player_id=v and date>current_date-40),'[]'::jsonb),
   'rpe',coalesce((select jsonb_agg(jsonb_build_object('date',date,'tipo',tipo,'min',min,'rpe',rpe)) from rpe where player_id=v and date>current_date-40),'[]'::jsonb),
   'messages',coalesce((select jsonb_agg(x order by (x->>'t')::bigint) from (select jsonb_build_object('t',_ms(t),'staff',from_staff,'body',body,'team',player_id is null) x from messages where player_id=v or player_id is null order by t desc limit 200) q),'[]'::jsonb),
   'read',coalesce((select _ms(player_read) from reads where player_id=v),0)); end $$;

create or replace function player_save_wellness(p_code text,p_date date,p_s int,p_f int,p_d int,p_e int,p_a int,p_h numeric,p_zona text[],p_c text) returns void language plpgsql security definer set search_path=public as $$
declare v uuid:=_pid(p_code); begin
  if p_date>current_date+1 or p_date<current_date-60 then raise exception 'fecha no válida'; end if;
  insert into wellness(player_id,date,s,f,d,e,a,h,zona,c) values(v,p_date,p_s,p_f,p_d,p_e,p_a,p_h,coalesce(p_zona,'{}'),left(coalesce(p_c,''),300))
  on conflict(player_id,date) do update set s=excluded.s,f=excluded.f,d=excluded.d,e=excluded.e,a=excluded.a,h=excluded.h,zona=excluded.zona,c=excluded.c,t=now(); end $$;

create or replace function player_save_rpe(p_code text,p_date date,p_tipo text,p_min int,p_rpe int) returns void language plpgsql security definer set search_path=public as $$
declare v uuid:=_pid(p_code); begin
  if p_date>current_date+1 or p_date<current_date-60 then raise exception 'fecha no válida'; end if;
  insert into rpe(player_id,date,tipo,min,rpe) values(v,p_date,left(p_tipo,30),p_min,p_rpe)
  on conflict(player_id,date,tipo) do update set min=excluded.min,rpe=excluded.rpe,t=now(); end $$;

create or replace function player_send(p_code text,p_body text) returns void language plpgsql security definer set search_path=public as $$
declare v uuid:=_pid(p_code); begin
  if length(trim(coalesce(p_body,'')))=0 then return; end if;
  insert into messages(player_id,from_staff,body) values(v,false,left(trim(p_body),500));
  insert into reads(player_id,player_read) values(v,now()) on conflict(player_id) do update set player_read=now(); end $$;

create or replace function player_mark_read(p_code text) returns void language plpgsql security definer set search_path=public as $$
declare v uuid:=_pid(p_code); begin
  insert into reads(player_id,player_read) values(v,now()) on conflict(player_id) do update set player_read=now(); end $$;

create or replace function staff_state(p_code text,p_days int default 60) returns jsonb language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code);
  return jsonb_build_object(
   'players',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'num',num,'pos',pos,'status',status,'note',note,'code',code)) from players),'[]'::jsonb),
   'wellness',coalesce((select jsonb_agg(jsonb_build_object('pid',player_id,'date',date,'s',s,'f',f,'d',d,'e',e,'a',a,'h',h,'zona',zona,'c',c)) from wellness where date>current_date-p_days),'[]'::jsonb),
   'rpe',coalesce((select jsonb_agg(jsonb_build_object('pid',player_id,'date',date,'tipo',tipo,'min',min,'rpe',rpe)) from rpe where date>current_date-p_days),'[]'::jsonb),
   'messages',coalesce((select jsonb_agg(x order by (x->>'t')::bigint) from (select jsonb_build_object('pid',player_id,'t',_ms(t),'staff',from_staff,'body',body) x from messages order by t desc limit 1500) q),'[]'::jsonb),
   'reads',coalesce((select jsonb_object_agg(player_id,_ms(staff_read)) from reads),'{}'::jsonb)); end $$;

create or replace function staff_save_player(p_code text,p_id uuid,p_name text,p_num int,p_pos text,p_status text,p_note text) returns uuid language plpgsql security definer set search_path=public as $$
declare v uuid; begin perform _staff(p_code);
  if p_status not in ('ok','lim','les','baja') then raise exception 'estado no válido'; end if;
  if p_id is null then
    insert into players(name,num,pos,status,note,code) values(left(trim(p_name),40),p_num,p_pos,p_status,coalesce(p_note,''),_newcode()) returning id into v;
  else
    update players set name=left(trim(p_name),40),num=p_num,pos=p_pos,status=p_status,note=left(coalesce(p_note,''),600) where id=p_id returning id into v;
  end if; return v; end $$;

create or replace function staff_delete_player(p_code text,p_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code); delete from players where id=p_id; end $$;

create or replace function staff_new_code(p_code text,p_id uuid) returns text language plpgsql security definer set search_path=public as $$
declare v text; begin perform _staff(p_code); v:=_newcode(); update players set code=v where id=p_id; return v; end $$;

create or replace function staff_send(p_code text,p_player uuid,p_body text) returns void language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code);
  if length(trim(coalesce(p_body,'')))=0 then return; end if;
  insert into messages(player_id,from_staff,body) values(p_player,true,left(trim(p_body),500));
  if p_player is not null then insert into reads(player_id,staff_read) values(p_player,now()) on conflict(player_id) do update set staff_read=now(); end if; end $$;

create or replace function staff_mark_read(p_code text,p_player uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code);
  insert into reads(player_id,staff_read) values(p_player,now()) on conflict(player_id) do update set staff_read=now(); end $$;

create or replace function staff_set_code(p_code text,p_new text) returns void language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code);
  if length(trim(coalesce(p_new,'')))<6 then raise exception 'el código necesita al menos 6 caracteres'; end if;
  if exists(select 1 from players where code=upper(trim(p_new))) then raise exception 'código no válido'; end if;
  update config set value=trim(p_new) where key='staff_code'; end $$;

grant execute on function login(text), player_state(text), player_save_wellness(text,date,int,int,int,int,int,numeric,text[],text),
  player_save_rpe(text,date,text,int,int), player_send(text,text), player_mark_read(text), staff_state(text,int),
  staff_save_player(text,uuid,text,int,text,text,text), staff_delete_player(text,uuid), staff_new_code(text,uuid),
  staff_send(text,uuid,text), staff_mark_read(text,uuid), staff_set_code(text,text) to anon, authenticated;
