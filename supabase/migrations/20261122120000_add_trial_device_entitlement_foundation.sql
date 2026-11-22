-- Northstar subscription trial and device entitlement foundation.
-- Development branch migration only. Do not apply to Production until reviewed and approved.
-- Device registrations are bound to the Supabase Auth session_id claim. Revoked devices
-- are denied by the guard even while their short-lived access JWT remains unexpired.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.account_pos_trials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null default (now() + interval '15 days'),
  created_at timestamptz not null default now(),
  constraint account_pos_trials_valid_window check (ends_at > started_at)
);

create table if not exists public.account_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_key uuid not null,
  auth_session_id uuid not null,
  device_type text not null check (device_type in ('phone','computer')),
  device_label text not null check (length(trim(device_label)) between 1 and 80),
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id),
  unique (user_id, device_key, auth_session_id)
);
create index if not exists account_devices_active_user_idx
  on public.account_devices(user_id, device_type) where revoked_at is null;
create index if not exists account_devices_session_idx
  on public.account_devices(auth_session_id) where revoked_at is null;

create table if not exists public.subscription_addons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  addon_code text not null check (addon_code = 'extra_device_slot'),
  quantity integer not null default 1 check (quantity between 1 and 20),
  amount_mmk integer not null default 11000 check (amount_mmk = 11000),
  billing_period text not null default 'monthly' check (billing_period = 'monthly'),
  status text not null default 'pending' check (status in ('pending','active','expired','cancelled','rejected')),
  payment_reference text,
  starts_at timestamptz,
  ends_at timestamptz,
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_addons_active_window check (
    status <> 'active' or (starts_at is not null and ends_at is not null and ends_at > starts_at)
  )
);
create index if not exists subscription_addons_active_user_idx
  on public.subscription_addons(user_id, ends_at) where status = 'active';

alter table public.account_pos_trials enable row level security;
alter table public.account_devices enable row level security;
alter table public.subscription_addons enable row level security;

drop policy if exists "Users read own POS trial" on public.account_pos_trials;
create policy "Users read own POS trial" on public.account_pos_trials
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "Users read own registered devices" on public.account_devices;
create policy "Users read own registered devices" on public.account_devices
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "Users read own device add-ons" on public.subscription_addons;
create policy "Users read own device add-ons" on public.subscription_addons
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.account_pos_trials, public.account_devices, public.subscription_addons from anon, authenticated;
grant select on public.account_pos_trials, public.account_devices, public.subscription_addons to authenticated;
grant all on public.account_pos_trials, public.account_devices, public.subscription_addons to service_role;

create or replace function public.ensure_account_pos_trial()
returns table(trial_started_at timestamptz, trial_ends_at timestamptz, trial_active boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  insert into public.account_pos_trials(user_id) values (v_user)
  on conflict (user_id) do nothing;
  return query
    select t.started_at, t.ends_at, (now() < t.ends_at)
    from public.account_pos_trials t where t.user_id = v_user;
end;
$$;

create or replace function public.register_account_device(
  p_device_key uuid,
  p_device_type text,
  p_device_label text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session uuid := nullif(auth.jwt()->>'session_id','')::uuid;
  v_limit integer := 2;
  v_active_count integer;
  v_type_count integer;
  v_existing public.account_devices%rowtype;
  v_addon_slots integer := 0;
begin
  if v_user is null or v_session is null then
    raise exception 'Authenticated session required' using errcode = '42501';
  end if;
  select exists(select 1 from public.platform_admins a where a.user_id=v_user) into v_is_admin;
  if p_device_key is null or p_device_type not in ('phone','computer')
     or p_device_label is null or length(trim(p_device_label)) not between 1 and 80 then
    raise exception 'Invalid device details' using errcode = '22023';
  end if;

  select * into v_existing from public.account_devices d
   where d.user_id=v_user and d.device_key=p_device_key and d.revoked_at is null
   order by d.registered_at desc limit 1;
  if found then
    update public.account_devices set last_seen_at=now(), device_label=trim(p_device_label), auth_session_id=v_session
     where id=v_existing.id;
    return jsonb_build_object('registered',true,'device_id',v_existing.id,'already_registered',true);
  end if;

  select coalesce(sum(a.quantity),0)::integer into v_addon_slots
  from public.subscription_addons a
  where a.user_id=v_user and a.addon_code='extra_device_slot' and a.status='active'
    and a.starts_at <= now() and a.ends_at > now();
  v_limit := 2 + v_addon_slots;

  select count(*)::integer into v_active_count from public.account_devices d
   where d.user_id=v_user and d.revoked_at is null;
  select count(*)::integer into v_type_count from public.account_devices d
   where d.user_id=v_user and d.device_type=p_device_type and d.revoked_at is null;
  if not v_is_admin and (v_active_count >= v_limit or v_type_count >= 1 + v_addon_slots) then
    raise exception 'Device limit reached. Revoke an existing device or purchase an extra device slot.' using errcode='P0001';
  end if;

  insert into public.account_devices(user_id,device_key,auth_session_id,device_type,device_label)
  values(v_user,p_device_key,v_session,p_device_type,trim(p_device_label))
  returning id into v_existing.id;
  return jsonb_build_object('registered',true,'device_id',v_existing.id,'already_registered',false,'device_limit',v_limit);
end;
$$;

create or replace function public.revoke_account_device(p_device_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required' using errcode='42501'; end if;
  update public.account_devices
     set revoked_at=now(), revoked_by=v_user
   where id=p_device_id and user_id=v_user and revoked_at is null;
  return found;
end;
$$;

create or replace function public.request_extra_device_slot()
returns uuid
language plpgsql
security definer
set search_path = ''
as $
declare v_user uuid := auth.uid(); v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='42501'; end if;
  insert into public.subscription_addons(user_id,addon_code,quantity,amount_mmk,billing_period,status)
  values(v_user,'extra_device_slot',1,11000,'monthly','pending')
  returning id into v_id;
  return v_id;
end;
$;

create or replace function public.review_extra_device_slot(
  p_addon_id uuid,
  p_approve boolean,
  p_payment_reference text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $
declare v_admin uuid := auth.uid();
begin
  if v_admin is null or not exists(select 1 from public.platform_admins a where a.user_id=v_admin) then
    raise exception 'Platform administrator required' using errcode='42501';
  end if;
  if p_approve and (p_payment_reference is null or length(trim(p_payment_reference)) < 4) then
    raise exception 'Verified merchant transaction reference required' using errcode='22023';
  end if;
  update public.subscription_addons
     set status=case when p_approve then 'active' else 'rejected' end,
         payment_reference=case when p_approve then trim(p_payment_reference) else payment_reference end,
         starts_at=case when p_approve then now() else starts_at end,
         ends_at=case when p_approve then now()+interval '1 month' else ends_at end,
         approved_by=v_admin, updated_at=now()
   where id=p_addon_id and status='pending';
  if not found then return false; end if;
  insert into public.audit_logs(user_id,actor_id,action,entity,entity_id,details)
  select a.user_id,v_admin,
         case when p_approve then 'device_addon_approved' else 'device_addon_rejected' end,
         'subscription_addon',a.id::text,
         jsonb_build_object('amount_mmk',a.amount_mmk,'quantity',a.quantity,'billing_period',a.billing_period)
    from public.subscription_addons a where a.id=p_addon_id;
  return true;
end;
$;

create or replace function public.current_account_device_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (auth.jwt()->>'session_id') is not null
    and exists (
      select 1 from public.account_devices d
       join auth.sessions s on s.id=d.auth_session_id and s.user_id=d.user_id
      where d.user_id=(select auth.uid())
        and d.auth_session_id=nullif(auth.jwt()->>'session_id','')::uuid
        and d.revoked_at is null
    );
$$;

create or replace function public.get_account_entitlements()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_admin boolean := false;
  v_trial public.account_pos_trials%rowtype;
  v_plan text;
  v_sub_end timestamptz;
  v_addon_slots integer := 0;
  v_device_count integer := 0;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select exists(select 1 from public.platform_admins a where a.user_id=v_user) into v_admin;
  insert into public.account_pos_trials(user_id) values(v_user) on conflict(user_id) do nothing;
  select * into v_trial from public.account_pos_trials where user_id=v_user;
  select s.plan_code,s.ends_at into v_plan,v_sub_end
    from public.subscriptions s
   where s.user_id=v_user and s.status='active' and s.plan_code <> 'free'
     and (s.ends_at is null or s.ends_at > now())
   order by s.starts_at desc limit 1;
  select coalesce(sum(a.quantity),0)::integer into v_addon_slots
    from public.subscription_addons a
   where a.user_id=v_user and a.status='active'
     and a.starts_at<=now() and a.ends_at>now();
  select count(*)::integer into v_device_count from public.account_devices d
   where d.user_id=v_user and d.revoked_at is null;
  return jsonb_build_object(
    'is_admin',v_admin,
    'plan_code',coalesce(v_plan,'free'),
    'subscription_active',v_plan is not null and (v_sub_end is null or v_sub_end>now()),
    'trial_started_at',v_trial.started_at,
    'trial_ends_at',v_trial.ends_at,
    'trial_active',now()<v_trial.ends_at,
    'pos_allowed',v_admin or (v_plan is not null) or now()<v_trial.ends_at,
    'included_device_slots',2,
    'extra_device_slots',v_addon_slots,
    'device_limit',2+v_addon_slots,
    'active_devices',v_device_count,
    'extra_device_price_mmk_monthly',11000
  );
end;
$$;

revoke all on function public.ensure_account_pos_trial() from public, anon;
revoke all on function public.register_account_device(uuid,text,text) from public, anon;
revoke all on function public.revoke_account_device(uuid) from public, anon;
revoke all on function public.current_account_device_is_active() from public, anon;\nrevoke all on function public.request_extra_device_slot() from public, anon;\nrevoke all on function public.review_extra_device_slot(uuid,boolean,text) from public, anon;
revoke all on function public.get_account_entitlements() from public, anon;
grant execute on function public.ensure_account_pos_trial() to authenticated;
grant execute on function public.register_account_device(uuid,text,text) to authenticated;
grant execute on function public.revoke_account_device(uuid) to authenticated;
grant execute on function public.current_account_device_is_active() to authenticated;\ngrant execute on function public.request_extra_device_slot() to authenticated;\ngrant execute on function public.review_extra_device_slot(uuid,boolean,text) to authenticated;
grant execute on function public.get_account_entitlements() to authenticated;

comment on table public.account_pos_trials is 'One immutable 15-day POS trial per user; created on first authenticated activation.';
comment on table public.account_devices is 'Active device registrations tied to Supabase Auth session_id; never stores refresh tokens.';
comment on table public.subscription_addons is 'Manually verified monthly recurring add-ons; one extra device slot costs 11000 MMK per month.';
