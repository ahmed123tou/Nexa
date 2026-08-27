-- NEXA SUPABASE SETUP
-- Run this in Supabase -> SQL Editor.
-- Then enable Email provider in Authentication -> Providers.
-- For testing, you can disable "Confirm email"; for real use, keep email confirmation enabled.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null,
  email text,
  avatar_url text,
  created_at timestamptz default now()
);

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz default now(),
  unique(user_id, friend_id),
  check(user_id <> friend_id)
);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);

drop policy if exists "profile insert own" on public.profiles;
create policy "profile insert own" on public.profiles for insert to authenticated with check (auth.uid() = id);

drop policy if exists "profile update own" on public.profiles;
create policy "profile update own" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "friendships readable" on public.friendships;
create policy "friendships readable" on public.friendships for select to authenticated
using (auth.uid() = user_id or auth.uid() = friend_id);

drop policy if exists "friendship create" on public.friendships;
create policy "friendship create" on public.friendships for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "friendship update recipient" on public.friendships;
create policy "friendship update recipient" on public.friendships for update to authenticated
using (auth.uid() = friend_id or auth.uid() = user_id);

-- Optional: automatically create a basic profile after email signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  base_username text;
begin
  base_username := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)), '[^a-zA-Z0-9_]', '', 'g'));
  base_username := left(base_username, 18);
  if base_username = '' then base_username := 'user'; end if;

  insert into public.profiles(id, username, display_name, email, avatar_url)
  values(
    new.id,
    base_username || '_' || substr(replace(new.id::text,'-',''),1,5),
    coalesce(new.raw_user_meta_data->>'display_name','Nexa User'),
    new.email,
    'https://api.dicebear.com/9.x/fun-emoji/svg?seed=' || new.id::text
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();
