-- Společný content kalendář: jeden řádek 'main' s celým kalendářem (JSON).
-- Zapisovat smí kdokoli s odkazem (anon klíč), mazat nikdo.
create table public.calendar (
  id text primary key check (id = 'main'),
  data jsonb not null check (octet_length(data::text) < 2000000),
  updated_at timestamptz not null default now()
);
alter table public.calendar enable row level security;
create policy "cist muze kazdy"    on public.calendar for select to anon, authenticated using (true);
create policy "vlozit muze kazdy"  on public.calendar for insert to anon, authenticated with check (id = 'main');
create policy "upravit muze kazdy" on public.calendar for update to anon, authenticated using (id = 'main') with check (id = 'main');

-- Historie: každá změna uloží předchozí verzi. Přes anon klíč není čitelná ani zapisovatelná,
-- obnovuje se ručně v Supabase (Table Editor → calendar_history). Drží posledních 1000 verzí.
create table public.calendar_history (
  version bigint generated always as identity primary key,
  data jsonb not null,
  saved_at timestamptz not null default now()
);
alter table public.calendar_history enable row level security;

create function public.calendar_keep_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    insert into calendar_history(data) values (old.data);
    delete from calendar_history where version <= (select max(version) - 1000 from calendar_history);
  end if;
  return new;
end $$;
revoke execute on function public.calendar_keep_history() from public, anon, authenticated;
create trigger calendar_history before insert or update on public.calendar
  for each row execute function public.calendar_keep_history();

-- Živé aktualizace pro ostatní otevřená okna
alter publication supabase_realtime add table public.calendar;
