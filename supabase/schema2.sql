-- ===== Extensiones =====
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ===== Perfiles =====
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text not null,
  email_confirmed boolean default false,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_select_own') then
    execute 'create policy "profiles_select_own" on public.profiles for select using (auth.uid() = id)';
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_insert_own') then
    execute 'create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid() = id)';
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_update_own') then
    execute 'create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id)';
  end if;
end $$;

-- Triggers con auth.users
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name, email, email_confirmed)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email, new.email_confirmed_at is not null)
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        email_confirmed = excluded.email_confirmed;
  return new;
end$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.sync_profile_email()
returns trigger language plpgsql security definer as $$
begin
  update public.profiles
     set email = new.email,
         email_confirmed = new.email_confirmed_at is not null
   where id = new.id;
  return new;
end$$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated after update on auth.users
for each row execute procedure public.sync_profile_email();

-- ===== Helpers =====
create or replace function public.request_header(name text)
returns text language sql stable as $$
  select coalesce((current_setting('request.headers', true)::jsonb ->> name), '');
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ===== Devices =====
create table if not exists public.devices (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_key_hash text not null,          -- hash del secreto del dispositivo
  name text not null,
  type text default 'unknown',
  ip text,
  added_at timestamptz default now(),
  last_seen_at timestamptz,
  constraint devices_user_name_unique unique (user_id, name)
);
create index if not exists devices_user_idx on public.devices (user_id);
alter table public.devices enable row level security;

create or replace function public.auth_device_id()
returns uuid
language plpgsql
security definer
stable
set search_path = public, extensions, pg_catalog, pg_temp
as $$
declare
  raw_key text := public.request_header('x-device-key');
  d_id uuid;
begin
  if raw_key is null or length(raw_key)=0 then
    return null;
  end if;
  select id into d_id
  from public.devices
  where extensions.crypt(raw_key, device_key_hash) = device_key_hash;
  return d_id;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_policies where tablename='devices' and policyname='devices_user_select_own') then
    execute 'create policy "devices_user_select_own" on public.devices for select using (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='devices' and policyname='devices_user_insert_own') then
    execute 'create policy "devices_user_insert_own" on public.devices for insert with check (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='devices' and policyname='devices_user_update_own') then
    execute 'create policy "devices_user_update_own" on public.devices for update using (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='devices' and policyname='devices_user_delete_own') then
    execute 'create policy "devices_user_delete_own" on public.devices for delete using (auth.uid() = user_id)';
  end if;
  if not exists (select 1 from pg_policies where tablename='devices' and policyname='devices_device_patch_self') then
    execute 'create policy "devices_device_patch_self" on public.devices for update using (id = public.auth_device_id()) with check (id = public.auth_device_id())';
  end if;
end $$;

-- ===== ENUMS (usar DO $$ ... $$ en lugar de IF NOT EXISTS) =====
do $$
begin
  if not exists (select 1 from pg_type where typname = 'sensor_kind') then
    execute 'create type public.sensor_kind as enum (''pir'',''mic'',''camera'',''other'')';
  end if;

  if not exists (select 1 from pg_type where typname = 'actuator_kind') then
    execute 'create type public.actuator_kind as enum (''servo'',''relay'',''buzzer'',''other'')';
  end if;
end
$$;

-- ===== Live signals (sin histórico; 1 fila por sensor) =====
create table if not exists public.live_signals (
  id uuid primary key default uuid_generate_v4(),
  device_id uuid not null references public.devices(id) on delete cascade,
  name text not null,                 -- p.ej. 'PIR_sala'
  kind public.sensor_kind not null,
  value_numeric double precision,
  value_text text,
  extra jsonb default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (device_id, name)
);
create index if not exists live_signals_device_idx on public.live_signals (device_id);
alter table public.live_signals enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename='live_signals' and policyname='live_user_select_own') then
    execute 'create policy "live_user_select_own" on public.live_signals for select using (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='live_signals' and policyname='live_device_insert_self') then
    execute 'create policy "live_device_insert_self" on public.live_signals for insert with check (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='live_signals' and policyname='live_device_update_self') then
    execute 'create policy "live_device_update_self" on public.live_signals for update using (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id())) with check (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id()))';
  end if;
end $$;

-- UPSERT en vivo (el dispositivo sobrescribe su fila de sensor)
create or replace function public.upsert_live_signal(
  _device_name text,                                -- opcional (para debug)
  _sensor_name text,
  _kind public.sensor_kind,
  _value_numeric double precision default null,
  _value_text text default null,
  _extra jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer as $$
declare
  did uuid := public.auth_device_id();
  sid uuid;
begin
  if did is null then
    raise exception 'unauthorized device';
  end if;

  update public.devices
     set last_seen_at = now(),
         ip = nullif(public.request_header('x-real-ip'), ip)
   where id = did;

  insert into public.live_signals (device_id, name, kind, value_numeric, value_text, extra, updated_at)
  values (did, _sensor_name, _kind, _value_numeric, _value_text, coalesce(_extra,'{}'::jsonb), now())
  on conflict (device_id, name) do update
    set kind          = excluded.kind,
        value_numeric = excluded.value_numeric,
        value_text    = excluded.value_text,
        extra         = excluded.extra,
        updated_at    = now()
  returning id into sid;

  return sid;
end;
$$;

-- ===== Actuadores + Cola de comandos =====
create table if not exists public.actuators (
  id uuid primary key default uuid_generate_v4(),
  device_id uuid not null references public.devices(id) on delete cascade,
  name text not null,
  kind public.actuator_kind not null,
  meta jsonb default '{}'::jsonb,
  unique(device_id, name)
);
alter table public.actuators enable row level security;

create table if not exists public.actuator_commands (
  id bigserial primary key,
  actuator_id uuid not null references public.actuators(id) on delete cascade,
  created_at timestamptz default now(),
  command jsonb not null,
  status text default 'pending',       -- pending|taken|done|error
  executed_at timestamptz
);
create index if not exists actuator_commands_pending_idx on public.actuator_commands (actuator_id, status, created_at);
alter table public.actuator_commands enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename='actuators' and policyname='actuators_user_select_own') then
    execute 'create policy "actuators_user_select_own" on public.actuators for select using (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuators' and policyname='actuators_user_manage_own') then
    execute 'create policy "actuators_user_manage_own" on public.actuators for all using (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid())) with check (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuators' and policyname='actuators_device_select_self') then
    execute 'create policy "actuators_device_select_self" on public.actuators for select using (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuators' and policyname='actuators_device_insert_self') then
    execute 'create policy "actuators_device_insert_self" on public.actuators for insert with check (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuators' and policyname='actuators_device_update_self') then
    execute 'create policy "actuators_device_update_self" on public.actuators for update using (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id())) with check (exists (select 1 from public.devices d where d.id = device_id and d.id = public.auth_device_id()))';
  end if;

  if not exists (select 1 from pg_policies where tablename='actuator_commands' and policyname='commands_user_select_own') then
    execute 'create policy "commands_user_select_own" on public.actuator_commands for select using (exists (select 1 from public.actuators a join public.devices d on d.id=a.device_id where a.id = actuator_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuator_commands' and policyname='commands_user_insert_own') then
    execute 'create policy "commands_user_insert_own" on public.actuator_commands for insert with check (exists (select 1 from public.actuators a join public.devices d on d.id=a.device_id where a.id = actuator_id and d.user_id = auth.uid()))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuator_commands' and policyname='commands_device_select_self') then
    execute 'create policy "commands_device_select_self" on public.actuator_commands for select using (exists (select 1 from public.actuators a where a.id = actuator_id and exists (select 1 from public.devices d where d.id = a.device_id and d.id = public.auth_device_id())))';
  end if;
  if not exists (select 1 from pg_policies where tablename='actuator_commands' and policyname='commands_device_update_self') then
    execute 'create policy "commands_device_update_self" on public.actuator_commands for update using (exists (select 1 from public.actuators a where a.id = actuator_id and exists (select 1 from public.devices d where d.id = a.device_id and d.id = public.auth_device_id())))';
  end if;
end $$;

-- ===== Storage: bucket camera_frames =====
create table if not exists public.device_remote_flags (
  device_id uuid primary key references public.devices(id) on delete cascade,
  ping_requested boolean default false,
  ping_requested_at timestamptz,
  ping_ack_at timestamptz,
  ping_status text default 'idle',
  ping_note text,
  forget_requested boolean default false,
  forget_requested_at timestamptz,
  forget_ack_at timestamptz,
  forget_processed_at timestamptz,
  forget_status text default 'idle',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.device_remote_flags enable row level security;

drop trigger if exists device_remote_flags_touch on public.device_remote_flags;

create trigger device_remote_flags_touch
before update on public.device_remote_flags
for each row execute procedure public.touch_updated_at();

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'device_remote_flags'
      and policyname = 'remote_flags_user_select'
  ) then
    execute 'create policy "remote_flags_user_select" on public.device_remote_flags for select using (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid()))';
  end if;
  if not exists (
    select 1 from pg_policies
    where tablename = 'device_remote_flags'
      and policyname = 'remote_flags_user_upsert'
  ) then
    execute 'create policy "remote_flags_user_upsert" on public.device_remote_flags for all using (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid())) with check (exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid()))';
  end if;
  if not exists (
    select 1 from pg_policies
    where tablename = 'device_remote_flags'
      and policyname = 'remote_flags_device_select'
  ) then
    execute 'create policy "remote_flags_device_select" on public.device_remote_flags for select using (device_id = public.auth_device_id())';
  end if;
  if not exists (
    select 1 from pg_policies
    where tablename = 'device_remote_flags'
      and policyname = 'remote_flags_device_update'
  ) then
    execute 'create policy "remote_flags_device_update" on public.device_remote_flags for update using (device_id = public.auth_device_id()) with check (device_id = public.auth_device_id())';
  end if;
end $$;

-- ===== Security Events =====
create table if not exists public.security_events (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  device_name text,
  label text,
  description text,
  image_url text,
  captured_at timestamptz not null default now(),
  family_member_id integer,
  family_member_name text,
  family_schedule_matched boolean,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists security_events_user_idx
  on public.security_events (user_id, captured_at desc);
create index if not exists security_events_device_idx
  on public.security_events (device_id, captured_at desc);

alter table public.security_events enable row level security;

drop trigger if exists security_events_touch on public.security_events;
create trigger security_events_touch
before update on public.security_events
for each row execute procedure public.touch_updated_at();

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'security_events'
      and policyname = 'security_events_select_own'
  ) then
    execute 'create policy "security_events_select_own" on public.security_events for select using (user_id = auth.uid())';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'security_events'
      and policyname = 'security_events_insert_own'
  ) then
    execute
      'create policy "security_events_insert_own" on public.security_events
       for insert with check (
         user_id = auth.uid()
         and exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid())
       )';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'security_events'
      and policyname = 'security_events_update_own'
  ) then
    execute
      'create policy "security_events_update_own" on public.security_events
       for update using (user_id = auth.uid())
       with check (
         user_id = auth.uid()
         and exists (select 1 from public.devices d where d.id = device_id and d.user_id = auth.uid())
       )';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'security_events'
      and policyname = 'security_events_delete_own'
  ) then
    execute
      'create policy "security_events_delete_own" on public.security_events
       for delete using (user_id = auth.uid())';
  end if;
end $$;

-- ===== Push notification tokens =====
create table if not exists public.user_push_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (user_id, token)
);

alter table public.user_push_tokens enable row level security;

drop trigger if exists user_push_tokens_touch on public.user_push_tokens;
create trigger user_push_tokens_touch
before update on public.user_push_tokens
for each row execute procedure public.touch_updated_at();

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'user_push_tokens'
      and policyname = 'user_push_tokens_select_own'
  ) then
    execute
      'create policy "user_push_tokens_select_own" on public.user_push_tokens
       for select using (user_id = auth.uid())';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'user_push_tokens'
      and policyname = 'user_push_tokens_insert_own'
  ) then
    execute
      'create policy "user_push_tokens_insert_own" on public.user_push_tokens
       for insert with check (user_id = auth.uid())';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'user_push_tokens'
      and policyname = 'user_push_tokens_update_own'
  ) then
    execute
      'create policy "user_push_tokens_update_own" on public.user_push_tokens
       for update using (user_id = auth.uid())
       with check (user_id = auth.uid())';
  end if;

  if not exists (
    select 1 from pg_policies
    where tablename = 'user_push_tokens'
      and policyname = 'user_push_tokens_delete_own'
  ) then
    execute
      'create policy "user_push_tokens_delete_own" on public.user_push_tokens
       for delete using (user_id = auth.uid())';
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit)
values ('camera_frames', 'camera_frames', false, null)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'camera_frames_device_insert'
  ) then
    execute $policy$
      create policy "camera_frames_device_insert"
      on storage.objects
      for insert
      with check (
        bucket_id = 'camera_frames'
        and public.auth_device_id() is not null
        and name like public.auth_device_id()::text || '/%'
      );
    $policy$;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'camera_frames_device_update'
  ) then
    execute $policy$
      create policy "camera_frames_device_update"
      on storage.objects
      for update
      using (
        bucket_id = 'camera_frames'
        and public.auth_device_id() is not null
        and name like public.auth_device_id()::text || '/%'
      )
      with check (
        bucket_id = 'camera_frames'
        and public.auth_device_id() is not null
        and name like public.auth_device_id()::text || '/%'
      );
    $policy$;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'camera_frames_device_select'
  ) then
    execute $policy$
      create policy "camera_frames_device_select"
      on storage.objects
      for select
      using (
        bucket_id = 'camera_frames'
        and (
          public.auth_device_id() is not null
          and name like public.auth_device_id()::text || '/%'
        )
      );
    $policy$;
  end if;
end $$;

-- RPC: alta de dispositivo (devuelve device_key en claro UNA vez)
create or replace function public.generate_device(_name text, _type text default 'esp32')
returns table(id uuid, device_key text)
language plpgsql security definer as $$
declare
  raw_key text := encode(extensions.gen_random_bytes(24), 'base64');
  hash_key text := extensions.crypt(raw_key, extensions.gen_salt('bf'));
begin
  insert into public.devices (id, user_id, device_key_hash, name, type)
  values (uuid_generate_v4(), auth.uid(), hash_key, _name, _type)
  returning devices.id into id;

  insert into public.device_remote_flags (device_id)
  values (id)
  on conflict (device_id) do nothing;

  device_key := raw_key;
  return next;
end;
$$;

-- RPC: dispositivo toma 1 comando pendiente
create or replace function public.device_next_command()
returns table(command_id bigint, actuator_id uuid, command jsonb)
language plpgsql security definer as $$
declare did uuid := public.auth_device_id();
begin
  if did is null then raise exception 'unauthorized device'; end if;

  update public.devices
     set last_seen_at = now(), ip = nullif(public.request_header('x-real-ip'), ip)
   where id = did;

  return query
  with a as (
    select a.id from public.actuators a where a.device_id = did
  ), c as (
    select ac.* from public.actuator_commands ac
    join a on a.id = ac.actuator_id
    where ac.status = 'pending'
    order by ac.created_at
    limit 1
  )
  update public.actuator_commands set status='taken'
  from c
  where actuator_commands.id = c.id
  returning actuator_commands.id, actuator_commands.actuator_id, actuator_commands.command;
end;
$$;

-- RPC: dispositivo marca comando ejecutado
create or replace function public.device_command_done(_command_id bigint, _ok boolean, _error text default null)
returns void
language plpgsql security definer as $$
declare did uuid := public.auth_device_id();
begin
  if did is null then raise exception 'unauthorized device'; end if;

  update public.actuator_commands ac
     set status = case when _ok then 'done' else 'error' end,
         executed_at = now(),
         command = ac.command || jsonb_build_object('device_note', coalesce(_error,''))
   where ac.id = _command_id
     and exists (select 1 from public.actuators a where a.id = ac.actuator_id and a.device_id = did);
end;
$$;

-- RPC: estado actual desde live_signals
create or replace function public.device_current_state(_device_id uuid)
returns jsonb
language plpgsql security definer as $$
declare
  user_id uuid := auth.uid();
  row record;
  payload jsonb := '{}'::jsonb;
  last_ts timestamptz := null;
begin
  if user_id is null then
    raise exception 'not authenticated';
  end if;

  for row in
    select ls.*
      from public.live_signals ls
      join public.devices d on d.id = ls.device_id
     where ls.device_id = _device_id
       and d.user_id = user_id
  loop
    payload := payload || jsonb_build_object(
      row.name,
      jsonb_strip_nulls(
        jsonb_build_object(
          'kind', row.kind,
          'value_numeric', row.value_numeric,
          'value_text', row.value_text,
          'extra', coalesce(row.extra, '{}'::jsonb),
          'updated_at', row.updated_at
        )
      )
    );

    if row.extra is not null then
      payload := payload || row.extra;
    end if;

    if last_ts is null or row.updated_at > last_ts then
      last_ts := row.updated_at;
    end if;
  end loop;

  if last_ts is not null then
    payload := payload || jsonb_build_object(
      'last_updated_at', last_ts
    );
  end if;

  return payload;
end;
$$;

create or replace function public.device_take_remote_flags()
returns jsonb
language plpgsql security definer as $$
declare
  did uuid := public.auth_device_id();
  flags record;
  payload jsonb := '{}'::jsonb;
begin
  if did is null then
    raise exception 'unauthorized device';
  end if;

  select *
    into flags
    from public.device_remote_flags
   where device_id = did
   for update;

  if not found then
    insert into public.device_remote_flags (device_id)
    values (did)
    returning * into flags;
  end if;

  if coalesce(flags.ping_requested, false) then
    if coalesce(flags.ping_status, 'idle') = 'pending' then
      update public.device_remote_flags
         set ping_status = 'ack',
             ping_ack_at = now(),
             updated_at = now()
       where device_id = did;
      payload := payload || jsonb_build_object('ping_requested', true);
    end if;
  end if;

  if coalesce(flags.forget_requested, false) then
    if coalesce(flags.forget_status, 'idle') = 'pending' then
      update public.device_remote_flags
         set forget_status = 'ack',
             forget_ack_at = now(),
             updated_at = now()
       where device_id = did;
      payload := payload || jsonb_build_object('forget_requested', true);
    end if;
  end if;

  return payload;
end;
$$;

create or replace function public.device_mark_remote_forget_done()
returns void
language plpgsql security definer as $$
declare
  did uuid := public.auth_device_id();
begin
  if did is null then
    raise exception 'unauthorized device';
  end if;

  update public.device_remote_flags
     set forget_status = 'done',
         forget_requested = false,
         forget_processed_at = now(),
         updated_at = now()
   where device_id = did;
end;
$$;

-- RPC: dispositivo asegura que exista su actuador principal
create or replace function public.device_upsert_actuator(
  _name text,
  _kind public.actuator_kind,
  _meta jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer as $$
declare
  did uuid := public.auth_device_id();
  aid uuid;
begin
  if did is null then
    raise exception 'unauthorized device';
  end if;

  insert into public.actuators (device_id, name, kind, meta)
  values (did, coalesce(_name, 'servo_main'), coalesce(_kind, 'servo'), coalesce(_meta, '{}'::jsonb))
  on conflict (device_id, name) do update
    set kind = excluded.kind,
        meta = excluded.meta
  returning id into aid;

  return aid;
end;
$$;
