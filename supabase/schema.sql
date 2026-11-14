-- =====================================================================
-- Plug'd database setup
-- Paste this whole file into Supabase > SQL Editor > New query > Run.
-- Safe to run more than once.
-- =====================================================================

-- ---------- Tables ----------
-- Each record is stored as JSON in "data", keyed by "id".
create table if not exists public.profiles     (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.gigs         (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.applications (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.reviews      (id text primary key, data jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now());
create table if not exists public.admins       (user_id text primary key);

alter table public.profiles     enable row level security;
alter table public.gigs         enable row level security;
alter table public.applications enable row level security;
alter table public.reviews      enable row level security;
alter table public.admins       enable row level security;

-- ---------- Helpers ----------
create or replace function public.uid_text() returns text
language sql stable as $$ select coalesce(auth.uid()::text, '') $$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid()::text)
$$;

-- ---------- Everyone can read (contact info is handled below) ----------
drop policy if exists "read profiles" on public.profiles;
create policy "read profiles" on public.profiles for select using (true);
drop policy if exists "read gigs" on public.gigs;
create policy "read gigs" on public.gigs for select using (true);
drop policy if exists "read applications" on public.applications;
create policy "read applications" on public.applications for select using (true);
drop policy if exists "read reviews" on public.reviews;
create policy "read reviews" on public.reviews for select using (true);
drop policy if exists "read admins" on public.admins;
create policy "read admins" on public.admins for select using (true);

-- ---------- Profiles: you write your own; admins can edit any (VIP, strikes) ----------
drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles for insert to authenticated
  with check (id = public.uid_text());
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update to authenticated
  using (id = public.uid_text() or public.is_admin())
  with check (id = public.uid_text() or public.is_admin());
drop policy if exists "admin delete profile" on public.profiles;
create policy "admin delete profile" on public.profiles for delete to authenticated
  using (id = public.uid_text() or public.is_admin());

-- Members can't give themselves VIP or clear their own strikes.
create or replace function public.protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then
      new.data := (new.data - 'vip') - 'strikes';
    else
      new.data := jsonb_set(jsonb_set(new.data, '{vip}', coalesce(old.data->'vip', 'false'::jsonb)),
                            '{strikes}', coalesce(old.data->'strikes', '0'::jsonb));
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists protect_profile on public.profiles;
create trigger protect_profile before insert or update on public.profiles
  for each row execute function public.protect_profile();

-- ---------- Gigs ----------
-- Posters create and manage their gigs. The booked performer (or the performer
-- holding an offer) can only touch the booking/confirmation fields.
drop policy if exists "insert own gig" on public.gigs;
create policy "insert own gig" on public.gigs for insert to authenticated
  with check (data->>'posterId' = public.uid_text());
drop policy if exists "update gig parties" on public.gigs;
create policy "update gig parties" on public.gigs for update to authenticated
  using (data->>'posterId' = public.uid_text()
      or data->>'bookedId' = public.uid_text()
      or data->'offer'->>'applicantId' = public.uid_text()
      or public.is_admin());
drop policy if exists "delete own gig" on public.gigs;
create policy "delete own gig" on public.gigs for delete to authenticated
  using (data->>'posterId' = public.uid_text() or public.is_admin());

create or replace function public.protect_gig() returns trigger
language plpgsql security definer set search_path = public as $$
declare me text := public.uid_text(); c jsonb; pay jsonb;
begin
  new.updated_at := now();
  if public.is_admin() or me = old.data->>'posterId' then
    new.data := jsonb_set(new.data, '{posterId}', old.data->'posterId');  -- poster never changes
    return new;
  end if;
  -- Performer accepting or declining an offer made to them
  if old.data->'offer'->>'applicantId' = me and coalesce(old.data->>'status','') = 'open' then
    if new.data->>'status' = 'booked' then
      new.data := old.data || jsonb_build_object(
        'status','booked','bookedId',me,
        'agreedPay', old.data->'offer'->'amount',
        'payPlan', coalesce(new.data->'payPlan', '"outside"'::jsonb),
        'hold', case when new.data->>'payPlan' = 'hold' then new.data->'hold' else null end,
        'bookedAt', to_jsonb(now()), 'offer', null);
    else
      new.data := old.data || jsonb_build_object('offer', null);
    end if;
    return new;
  end if;
  -- Booked performer: may only mark completed and confirm payment received
  if old.data->>'bookedId' = me then
    c := coalesce(old.data->'confirms','{}'::jsonb);
    if (new.data->'confirms') ? me and (old.data->'confirms'->me) is null then
      c := c || jsonb_build_object(me, new.data->'confirms'->me);
    end if;
    pay := old.data->'payment';
    if pay is not null and jsonb_typeof(pay) = 'object' and (new.data->'payment'->'receivedAt') is not null then
      pay := pay || jsonb_build_object('receivedAt', new.data->'payment'->'receivedAt');
    end if;
    new.data := old.data || jsonb_build_object('confirms', c) || (case when pay is null then '{}'::jsonb else jsonb_build_object('payment', pay) end);
    return new;
  end if;
  return old;
end $$;
drop trigger if exists protect_gig on public.gigs;
create trigger protect_gig before update on public.gigs
  for each row execute function public.protect_gig();

-- ---------- Sign-ups (applications) ----------
drop policy if exists "insert own application" on public.applications;
create policy "insert own application" on public.applications for insert to authenticated
  with check (data->>'applicantId' = public.uid_text()
          and id = (data->>'gigId') || '__' || public.uid_text());
drop policy if exists "update application" on public.applications;
create policy "update application" on public.applications for update to authenticated
  using (data->>'applicantId' = public.uid_text()
      or public.is_admin()
      or exists (select 1 from public.gigs g where g.id = applications.data->>'gigId' and g.data->>'posterId' = public.uid_text()));
drop policy if exists "delete own application" on public.applications;
create policy "delete own application" on public.applications for delete to authenticated
  using (data->>'applicantId' = public.uid_text() or public.is_admin());

-- ---------- Reviews: only the two sides of a completed gig, once each ----------
drop policy if exists "insert review" on public.reviews;
create policy "insert review" on public.reviews for insert to authenticated
  with check (
    reviews.data->>'authorId' = public.uid_text()
    and reviews.id = (reviews.data->>'gigId') || '__' || public.uid_text()
    and (reviews.data->>'stars')::int between 1 and 5
    and exists (
      select 1 from public.gigs g
      where g.id = reviews.data->>'gigId'
        and g.data->>'status' = 'booked'
        and g.data->'confirms' ? (g.data->>'bookedId')
        and ((g.data->>'posterId' = public.uid_text() and reviews.data->>'aboutId' = g.data->>'bookedId')
          or (g.data->>'bookedId' = public.uid_text() and reviews.data->>'aboutId' = g.data->>'posterId'))
    ));
drop policy if exists "admin delete review" on public.reviews;
create policy "admin delete review" on public.reviews for delete to authenticated
  using (public.is_admin() or reviews.data->>'authorId' = public.uid_text());

-- ---------- Private contact info ----------
-- Only you, admins, and the other side of a booking you're in can read it.
create table if not exists public.contacts (user_id text primary key, contact text not null default '', updated_at timestamptz not null default now());
alter table public.contacts enable row level security;
drop policy if exists "read contacts when booked" on public.contacts;
create policy "read contacts when booked" on public.contacts for select to authenticated
  using (user_id = public.uid_text() or public.is_admin() or exists (
    select 1 from public.gigs g where g.data->>'status' = 'booked'
      and ((g.data->>'posterId' = public.uid_text() and g.data->>'bookedId' = contacts.user_id)
        or (g.data->>'bookedId' = public.uid_text() and g.data->>'posterId' = contacts.user_id))));
drop policy if exists "write own contact" on public.contacts;
create policy "write own contact" on public.contacts for insert to authenticated with check (user_id = public.uid_text());
drop policy if exists "update own contact" on public.contacts;
create policy "update own contact" on public.contacts for update to authenticated using (user_id = public.uid_text()) with check (user_id = public.uid_text());

-- ---------- Live updates ----------
do $$ begin
  begin alter publication supabase_realtime add table public.profiles;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.gigs;         exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.applications; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.reviews;      exception when duplicate_object then null; end;
end $$;

-- ---------- Video uploads (20 MB max, videos only) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', true, 20971520, array['video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set public = true, file_size_limit = 20971520,
  allowed_mime_types = array['video/mp4','video/quicktime','video/webm'];

drop policy if exists "upload own videos" on storage.objects;
create policy "upload own videos" on storage.objects for insert to authenticated
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "delete own videos" on storage.objects;
create policy "delete own videos" on storage.objects for delete to authenticated
  using (bucket_id = 'videos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
