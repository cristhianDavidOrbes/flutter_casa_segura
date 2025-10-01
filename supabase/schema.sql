-- Supabase setup script for Casa Segura auth
create extension if not exists "uuid-ossp";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text not null,
  email_confirmed boolean default false,
  created_at timestamp with time zone default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email, email_confirmed)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->> 'full_name', ''),
    new.email,
    new.email_confirmed_at is not null
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        email_confirmed = excluded.email_confirmed;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.sync_profile_email()
returns trigger as $$
begin
  update public.profiles
    set email = new.email,
        email_confirmed = new.email_confirmed_at is not null
    where id = new.id;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update on auth.users
  for each row execute procedure public.sync_profile_email();

create table if not exists public.devices (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null,
  name text not null,
  type text,
  ip text,
  added_at timestamp with time zone default now(),
  last_seen_at timestamp with time zone,
  constraint devices_user_device_key_unique unique (user_id, device_key)
);

alter table public.devices enable row level security;

create policy "devices_select_own" on public.devices
  for select using (auth.uid() = user_id);

create policy "devices_insert_own" on public.devices
  for insert with check (auth.uid() = user_id);

create policy "devices_update_own" on public.devices
  for update using (auth.uid() = user_id);

create policy "devices_delete_own" on public.devices
  for delete using (auth.uid() = user_id);
