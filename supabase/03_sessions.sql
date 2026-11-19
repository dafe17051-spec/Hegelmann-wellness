-- Session duration is set by the staff per day and session type; players only send RPE.
alter table rpe alter column min drop not null;

create table if not exists sessions(
  date date not null, tipo text not null, min int not null check (min between 1 and 400),
  t timestamptz not null default now(), primary key(date,tipo));
alter table sessions enable row level security;

create or replace function staff_sessions(p_code text,p_days int default 60) returns jsonb language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code);
  return coalesce((select jsonb_agg(jsonb_build_object('date',date,'tipo',tipo,'min',min)) from sessions where date>current_date-least(greatest(coalesce(p_days,60),1),3650)),'[]'::jsonb); end $$;

-- p_min null removes the duration for that day and type
create or replace function staff_save_session(p_code text,p_date date,p_tipo text,p_min int) returns void language plpgsql security definer set search_path=public as $$
begin perform _staff(p_code);
  if p_date>current_date+1 then raise exception 'invalid date'; end if;
  if p_min is null then delete from sessions where date=p_date and tipo=left(p_tipo,30);
  else insert into sessions(date,tipo,min) values(p_date,left(p_tipo,30),p_min)
    on conflict(date,tipo) do update set min=excluded.min,t=now(); end if; end $$;

grant execute on function staff_sessions(text,int), staff_save_session(text,date,text,int) to anon, authenticated;
