create table if not exists public.chalkboard (
  id text primary key check (id = 'owner'),
  image text not null check (length(image) <= 900000),
  updated_at timestamptz not null default now()
);

create table if not exists public.mail_owners (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.letters (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_name text not null check (length(sender_name) <= 40),
  body text not null check (length(body) between 3 and 1200),
  ink text not null check (ink in ('#1d3a8a', '#1c1c1c', '#a31f1f')),
  created_at timestamptz not null default now(),
  opened_at timestamptz
);

alter table public.chalkboard enable row level security;
alter table public.mail_owners enable row level security;
alter table public.letters enable row level security;

drop policy if exists "Anyone can view the shared chalkboard" on public.chalkboard;
create policy "Anyone can view the shared chalkboard"
  on public.chalkboard for select to anon, authenticated using (true);

drop policy if exists "Anyone can create the shared chalkboard" on public.chalkboard;
create policy "Anyone can create the shared chalkboard"
  on public.chalkboard for insert to anon, authenticated with check (true);

drop policy if exists "Anyone can update the shared chalkboard" on public.chalkboard;
create policy "Anyone can update the shared chalkboard"
  on public.chalkboard for update to anon, authenticated using (true) with check (true);

drop policy if exists "Users can identify themselves as mail owners" on public.mail_owners;
create policy "Users can identify themselves as mail owners"
  on public.mail_owners for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "Senders and the owner can read letters" on public.letters;
create policy "Senders and the owner can read letters"
  on public.letters for select to authenticated
  using (
    sender_id = (select auth.uid())
    or exists (
      select 1 from public.mail_owners
      where user_id = (select auth.uid())
    )
  );

drop policy if exists "Anonymous visitors can send letters" on public.letters;
create policy "Anonymous visitors can send letters"
  on public.letters for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select auth.jwt()->>'is_anonymous') = 'true'
  );

drop policy if exists "Only the owner can update letters" on public.letters;
create policy "Only the owner can update letters"
  on public.letters for update to authenticated
  using (
    exists (select 1 from public.mail_owners where user_id = (select auth.uid()))
  )
  with check (
    exists (select 1 from public.mail_owners where user_id = (select auth.uid()))
  );

drop policy if exists "Only the owner can delete letters" on public.letters;
create policy "Only the owner can delete letters"
  on public.letters for delete to authenticated
  using (
    exists (select 1 from public.mail_owners where user_id = (select auth.uid()))
  );

grant select, insert, update on public.chalkboard to anon, authenticated;
grant select, insert, update, delete on public.letters to authenticated;
grant select on public.mail_owners to authenticated;

create or replace function public.enforce_anonymous_letter_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sent_count integer;
begin
  if new.sender_id is distinct from (select auth.uid())
     or (select auth.jwt()->>'is_anonymous') is distinct from 'true' then
    raise exception 'anonymous sender required' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.sender_id::text, 0)
  );

  select count(*) into sent_count
  from public.letters
  where sender_id = new.sender_id;

  if sent_count >= 30 then
    raise exception 'too_many' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_anonymous_letter_limit() from public;
drop trigger if exists enforce_anonymous_letter_limit on public.letters;
create trigger enforce_anonymous_letter_limit
  before insert on public.letters
  for each row execute function public.enforce_anonymous_letter_limit();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chalkboard'
  ) then
    alter publication supabase_realtime add table public.chalkboard;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'letters'
  ) then
    alter publication supabase_realtime add table public.letters;
  end if;
end
$$;
