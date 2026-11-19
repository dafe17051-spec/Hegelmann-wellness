-- 1RM tests (one row per player, exercise and test date; the latest date is the current value)
create table if not exists onerm(
  player_id uuid not null references players(id) on delete cascade,
  exercise text not null check (exercise in ('squat','bench','benchpull','hipthrust','deadlift')),
  date date not null, kg numeric not null check (kg > 0 and kg < 600),
  t timestamptz not null default now(), primary key(player_id,exercise,date));
alter table onerm enable row level security;

create or replace function _onerm_json(p_player uuid) returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('pid',player_id,'ex',exercise,'date',date,'kg',kg) order by date),'[]'::jsonb)
  from onerm where p_player is null or player_id=p_player $$;
revoke all on function _onerm_json(uuid) from public, anon, authenticated;

create or replace function staff_onerm(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code); return _onerm_json(null); end $$;

create or replace function player_onerm(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare v uuid:=_pid(p_code); begin return _onerm_json(v); end $$;

-- p_values: {"squat":120,"bench":null,...}; a number saves it for that date, null removes that date's value
create or replace function staff_save_onerm(p_code text,p_player uuid,p_date date,p_values jsonb) returns void language plpgsql security definer set search_path=public as $$
declare k text; v jsonb; begin perform _staff(p_code);
  if p_date>current_date+1 then raise exception 'invalid date'; end if;
  for k,v in select * from jsonb_each(p_values) loop
    if k not in ('squat','bench','benchpull','hipthrust','deadlift') then raise exception 'invalid exercise'; end if;
    if v is null or jsonb_typeof(v)='null' then delete from onerm where player_id=p_player and exercise=k and date=p_date;
    else insert into onerm(player_id,exercise,date,kg) values(p_player,k,p_date,(v#>>'{}')::numeric)
      on conflict(player_id,exercise,date) do update set kg=excluded.kg,t=now(); end if;
  end loop; end $$;

grant execute on function staff_onerm(text), player_onerm(text), staff_save_onerm(text,uuid,date,jsonb) to anon, authenticated;
notify pgrst, 'reload schema';
