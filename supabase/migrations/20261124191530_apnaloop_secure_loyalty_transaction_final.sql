-- ApnaLoop secure loyalty transaction foundation.
-- Mirrors the live Supabase state: short-lived QR, India-day stamps, 10-stamp rewards,
-- one-time six-digit redemption, brute-force throttling, private privileged functions,
-- and realtime refresh feeds. PostgreSQL 17 / Supabase project apnaloop-live.


create schema if not exists private;
create table if not exists public.qr_sessions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  issued_by uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique check (length(token_hash)=64),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create table if not exists public.reward_claims (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  customer_user_id uuid not null references auth.users(id) on delete restrict,
  loyalty_card_id uuid not null references public.loyalty_cards(id) on delete restrict,
  reward_id uuid references public.rewards(id) on delete set null,
  title text not null,
  code_plaintext char(6) not null check (code_plaintext ~ '^[0-9]{6}$'),
  code_hash text not null unique,
  status text not null default 'unlocked' check (status in ('unlocked','redeemed','expired','revoked')),
  unlocked_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '30 days'),
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.reward_redemption_attempts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded boolean not null default false
);
create index if not exists qr_sessions_shop_expiry_idx on public.qr_sessions(shop_id,expires_at desc);
create index if not exists qr_sessions_issued_by_idx on public.qr_sessions(issued_by);
create index if not exists reward_claims_customer_shop_status_idx on public.reward_claims(customer_user_id,shop_id,status,unlocked_at desc);
create index if not exists reward_claims_shop_status_idx on public.reward_claims(shop_id,status,unlocked_at desc);
create index if not exists reward_claims_loyalty_card_id_idx on public.reward_claims(loyalty_card_id);
create index if not exists reward_claims_redeemed_by_idx on public.reward_claims(redeemed_by);
create index if not exists reward_claims_reward_id_idx on public.reward_claims(reward_id);
create index if not exists reward_redemption_attempts_actor_window_idx on public.reward_redemption_attempts(shop_id,actor_user_id,attempted_at desc);
create index if not exists reward_redemption_attempts_actor_user_id_idx on public.reward_redemption_attempts(actor_user_id);
create index if not exists customer_rewards_redeemed_by_idx on public.customer_rewards(redeemed_by);
create index if not exists customer_rewards_reward_id_idx on public.customer_rewards(reward_id);
alter table public.qr_sessions enable row level security;
alter table public.reward_claims enable row level security;
alter table public.reward_redemption_attempts enable row level security;
revoke all on public.qr_sessions,public.reward_claims,public.reward_redemption_attempts from public,anon,authenticated;


CREATE OR REPLACE FUNCTION private.apnaloop_claim_shop_stamp(p_shop_id uuid, p_qr_token text, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid:=auth.uid(); v_shop public.shops%rowtype; v_qr public.qr_sessions%rowtype;
  v_card public.loyalty_cards%rowtype; v_stamp public.stamps%rowtype; v_stamp_id uuid;
  v_stamp_count integer; v_reward_id uuid; v_reward_title text; v_reward_code text;
  v_reward_unlocked boolean:=false; v_random bytea; v_random_number bigint;
  v_now timestamptz:=now(); v_day date:=(now() at time zone 'Asia/Kolkata')::date;
  v_existing_reward public.reward_claims%rowtype;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_shop_id is null or p_qr_token is null or length(p_qr_token)<>64 or p_idempotency_key is null then raise exception 'INVALID_STAMP_REQUEST'; end if;
  select * into v_shop from public.shops where id=p_shop_id and is_active=true;
  if not found then raise exception 'SHOP_NOT_ACTIVE'; end if;
  select * into v_qr from public.qr_sessions where shop_id=p_shop_id
    and token_hash=encode(extensions.digest(p_qr_token,'sha256'),'hex') and expires_at>v_now;
  if not found then raise exception 'QR_SESSION_EXPIRED_OR_INVALID'; end if;
  select * into v_stamp from public.stamps where idempotency_key=p_idempotency_key and shop_id=p_shop_id and customer_user_id=v_uid;
  if found then
    select * into v_existing_reward from public.reward_claims where shop_id=p_shop_id and customer_user_id=v_uid
      and status='unlocked' and expires_at>now()
      and unlocked_at between v_stamp.created_at-interval '2 seconds' and v_stamp.created_at+interval '2 seconds'
      order by unlocked_at desc limit 1;
    select stamp_count into v_stamp_count from public.loyalty_cards where shop_id=p_shop_id and customer_user_id=v_uid;
    return jsonb_build_object('ok',true,'stamp_id',v_stamp.id,'created_at',v_stamp.created_at,
      'stamp_count',case when v_existing_reward.id is not null then 10 else coalesce(v_stamp_count,0) end,
      'reward_unlocked',v_existing_reward.id is not null,'reward_title',v_existing_reward.title,
      'reward_code',v_existing_reward.code_plaintext,'idempotent_replay',true);
  end if;
  insert into public.loyalty_cards(shop_id,customer_user_id,stamp_count,reward_count)
  values(p_shop_id,v_uid,0,0) on conflict(shop_id,customer_user_id) do nothing;
  select * into v_card from public.loyalty_cards where shop_id=p_shop_id and customer_user_id=v_uid for update;
  if exists(select 1 from public.stamps where shop_id=p_shop_id and customer_user_id=v_uid and stamp_date=v_day) then
    raise exception 'STAMP_ALREADY_CLAIMED_TODAY';
  end if;
  if exists(select 1 from public.reward_claims where shop_id=p_shop_id and customer_user_id=v_uid and status='unlocked' and expires_at>v_now) then
    raise exception 'REWARD_PENDING_REDEMPTION';
  end if;
  insert into public.stamps(shop_id,customer_user_id,loyalty_card_id,issued_by,stamp_date,idempotency_key)
  values(p_shop_id,v_uid,v_card.id,v_qr.issued_by,v_day,p_idempotency_key) returning id into v_stamp_id;
  insert into public.stamp_events(shop_id,customer_user_id,loyalty_card_id,issued_by,idempotency_key,note)
  values(p_shop_id,v_uid,v_card.id,v_qr.issued_by,p_idempotency_key,'QR verified stamp');
  v_stamp_count:=v_card.stamp_count+1;
  if v_stamp_count>=10 then
    select r.id,r.title into v_reward_id,v_reward_title from public.rewards r
      where r.shop_id=p_shop_id and r.is_active=true and r.stamps_required=10 order by r.created_at asc limit 1;
    if v_reward_title is null then v_reward_title:=coalesce(v_shop.description,'10 stamps reward'); end if;
    v_random:=extensions.gen_random_bytes(4);
    v_random_number:=get_byte(v_random,0)::bigint*16777216+get_byte(v_random,1)::bigint*65536+get_byte(v_random,2)::bigint*256+get_byte(v_random,3)::bigint;
    v_reward_code:=lpad((v_random_number%900000+100000)::text,6,'0');
    insert into public.reward_claims(shop_id,customer_user_id,loyalty_card_id,reward_id,title,code_plaintext,code_hash,status,unlocked_at,expires_at)
    values(p_shop_id,v_uid,v_card.id,v_reward_id,v_reward_title,v_reward_code,
      encode(extensions.digest(v_reward_code||':'||p_shop_id::text||':'||v_uid::text,'sha256'),'hex'),'unlocked',v_now,v_now+interval '30 days');
    update public.loyalty_cards set stamp_count=0,reward_count=reward_count+1,updated_at=v_now where id=v_card.id;
    v_reward_unlocked:=true;
  else
    update public.loyalty_cards set stamp_count=v_stamp_count,updated_at=v_now where id=v_card.id;
  end if;
  insert into public.audit_logs(actor_user_id,shop_id,action,entity_type,entity_id,metadata)
  values(v_uid,p_shop_id,'STAMP_ISSUED','stamp',v_stamp_id::text,jsonb_build_object('stamp_date',v_day,'reward_unlocked',v_reward_unlocked));
  return jsonb_build_object('ok',true,'stamp_id',v_stamp_id,'created_at',v_now,'stamp_count',v_stamp_count,
    'reward_unlocked',v_reward_unlocked,'reward_title',case when v_reward_unlocked then v_reward_title else null end,
    'reward_code',case when v_reward_unlocked then v_reward_code else null end);
exception when unique_violation then raise exception 'STAMP_ALREADY_CLAIMED_TODAY';
end; $function$


CREATE OR REPLACE FUNCTION private.apnaloop_get_customer_loyalty(p_shop_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid:=auth.uid(); v_card public.loyalty_cards%rowtype;
  v_stamps jsonb; v_reward jsonb; v_last_unlock timestamptz;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists(select 1 from public.shops where id=p_shop_id and is_active=true) then raise exception 'SHOP_NOT_ACTIVE'; end if;
  select * into v_card from public.loyalty_cards where shop_id=p_shop_id and customer_user_id=v_uid;
  if not found then return jsonb_build_object('stamp_count',0,'stamps','[]'::jsonb,'unlocked_reward',null); end if;
  select max(unlocked_at) into v_last_unlock from public.reward_claims where shop_id=p_shop_id and customer_user_id=v_uid;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'created_at',x.created_at,'stamp_date',x.stamp_date) order by x.created_at asc),'[]'::jsonb)
    into v_stamps from (
      select s.id,s.created_at,s.stamp_date from public.stamps s
      where s.shop_id=p_shop_id and s.customer_user_id=v_uid and (v_last_unlock is null or s.created_at>v_last_unlock)
      order by s.created_at desc limit 10
    ) x;
  select jsonb_build_object('id',rc.id,'title',rc.title,'code',rc.code_plaintext,'expires_at',rc.expires_at,'unlocked_at',rc.unlocked_at)
    into v_reward from public.reward_claims rc
    where rc.shop_id=p_shop_id and rc.customer_user_id=v_uid and rc.status='unlocked' and rc.expires_at>now()
    order by rc.unlocked_at desc limit 1;
  return jsonb_build_object('stamp_count',v_card.stamp_count,'reward_count',v_card.reward_count,'stamps',v_stamps,'unlocked_reward',v_reward);
end; $function$


CREATE OR REPLACE FUNCTION private.apnaloop_get_shop_dashboard(p_shop_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_uid uuid:=auth.uid(); v_stats jsonb; v_activity jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists(select 1 from public.shops s where s.id=p_shop_id and
    (s.owner_user_id=v_uid or exists(select 1 from public.shop_owners so where so.shop_id=s.id and so.user_id=v_uid))) then
    raise exception 'SHOP_OWNER_REQUIRED';
  end if;
  select jsonb_build_object(
    'today_stamps',(select count(*) from public.stamps where shop_id=p_shop_id and stamp_date=(now() at time zone 'Asia/Kolkata')::date),
    'repeat_customers',(select count(distinct customer_user_id) from public.stamps where shop_id=p_shop_id and created_at>=now()-interval '7 days'),
    'total_customers',(select count(distinct customer_user_id) from public.stamps where shop_id=p_shop_id)
  ) into v_stats;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'shop_id',a.shop_id,'customer_id',a.customer_id,
    'customer_name',a.customer_name,'customer_phone',a.customer_phone,'created_at',a.created_at,'status','active','stamp_count',a.stamp_count)
    order by a.created_at desc),'[]'::jsonb) into v_activity
  from (
    select st.id,st.shop_id,st.customer_user_id as customer_id,coalesce(c.display_name,'Customer') as customer_name,
      c.phone_e164 as customer_phone,st.created_at,coalesce(lc.stamp_count,0) as stamp_count
    from public.stamps st left join public.customers c on c.id=st.customer_user_id
      left join public.loyalty_cards lc on lc.shop_id=st.shop_id and lc.customer_user_id=st.customer_user_id
    where st.shop_id=p_shop_id order by st.created_at desc limit 12
  ) a;
  return jsonb_build_object('stats',v_stats,'recent_activity',v_activity);
end; $function$


CREATE OR REPLACE FUNCTION private.apnaloop_issue_shop_qr_session(p_shop_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare v_uid uuid := auth.uid(); v_token text; v_expires timestamptz := now() + interval '2 minutes';
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not exists (select 1 from public.shops s where s.id=p_shop_id and s.is_active=true
    and (s.owner_user_id=v_uid or exists(select 1 from public.shop_owners so where so.shop_id=s.id and so.user_id=v_uid))) then
    raise exception 'SHOP_OWNER_REQUIRED';
  end if;
  delete from public.qr_sessions where shop_id=p_shop_id and expires_at < now()-interval '10 minutes';
  v_token := encode(extensions.gen_random_bytes(32),'hex');
  insert into public.qr_sessions(shop_id,issued_by,token_hash,expires_at)
  values(p_shop_id,v_uid,encode(extensions.digest(v_token,'sha256'),'hex'),v_expires);
  return jsonb_build_object('token',v_token,'expires_at',v_expires);
end; $function$


CREATE OR REPLACE FUNCTION private.apnaloop_redeem_customer_reward(p_shop_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid:=auth.uid(); v_claim public.reward_claims%rowtype;
  v_attempt_id uuid; v_attempt_count integer;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_code is null or p_code !~ '^[0-9]{6}$' then return jsonb_build_object('ok',false,'message','6-digit code valid nahi hai.'); end if;
  if not exists(select 1 from public.shops s where s.id=p_shop_id and
    (s.owner_user_id=v_uid or exists(select 1 from public.shop_owners so where so.shop_id=s.id and so.user_id=v_uid))) then
    raise exception 'SHOP_OWNER_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_shop_id::text||':'||v_uid::text,0));
  delete from public.reward_redemption_attempts where shop_id=p_shop_id and actor_user_id=v_uid and attempted_at<now()-interval '90 days';

  select count(*) into v_attempt_count from public.reward_redemption_attempts
  where shop_id=p_shop_id and actor_user_id=v_uid and attempted_at>now()-interval '15 minutes';
  if v_attempt_count>=10 then return jsonb_build_object('ok',false,'message','Bahut attempts ho gaye. 15 minute baad dobara try karein.'); end if;

  insert into public.reward_redemption_attempts(shop_id,actor_user_id)
  values(p_shop_id,v_uid) returning id into v_attempt_id;

  select * into v_claim from public.reward_claims rc where rc.shop_id=p_shop_id
    and rc.code_hash=encode(extensions.digest(p_code||':'||p_shop_id::text||':'||rc.customer_user_id::text,'sha256'),'hex')
    for update;
  if not found then return jsonb_build_object('ok',false,'message','Code galat hai ya expire ho chuka hai.'); end if;
  if v_claim.status<>'unlocked' or v_claim.redeemed_at is not null then return jsonb_build_object('ok',false,'message','Yeh reward pehle hi redeem ho chuka hai.'); end if;
  if v_claim.expires_at<=now() then
    update public.reward_claims set status='expired' where id=v_claim.id;
    return jsonb_build_object('ok',false,'message','Reward code expire ho gaya hai.');
  end if;

  insert into public.reward_redemptions(shop_id,customer_user_id,loyalty_card_id,redeemed_by,idempotency_key)
  values(p_shop_id,v_claim.customer_user_id,v_claim.loyalty_card_id,v_uid,gen_random_uuid());
  update public.reward_claims set status='redeemed',redeemed_at=now(),redeemed_by=v_uid where id=v_claim.id;
  update public.reward_redemption_attempts set succeeded=true where id=v_attempt_id;
  insert into public.audit_logs(actor_user_id,shop_id,action,entity_type,entity_id,metadata)
  values(v_uid,p_shop_id,'REWARD_REDEEMED','reward_claim',v_claim.id::text,
    jsonb_build_object('customer_user_id',v_claim.customer_user_id,'title',v_claim.title));
  return jsonb_build_object('ok',true,'reward_title',v_claim.title,'customer_user_id',v_claim.customer_user_id,'redeemed_at',now());
end; $function$


grant usage on schema private to authenticated;
revoke all on function private.apnaloop_issue_shop_qr_session(uuid) from public,anon;
revoke all on function private.apnaloop_claim_shop_stamp(uuid,text,uuid) from public,anon;
revoke all on function private.apnaloop_get_customer_loyalty(uuid) from public,anon;
revoke all on function private.apnaloop_get_shop_dashboard(uuid) from public,anon;
revoke all on function private.apnaloop_redeem_customer_reward(uuid,text) from public,anon;
grant execute on function private.apnaloop_issue_shop_qr_session(uuid) to authenticated;
grant execute on function private.apnaloop_claim_shop_stamp(uuid,text,uuid) to authenticated;
grant execute on function private.apnaloop_get_customer_loyalty(uuid) to authenticated;
grant execute on function private.apnaloop_get_shop_dashboard(uuid) to authenticated;
grant execute on function private.apnaloop_redeem_customer_reward(uuid,text) to authenticated;
create or replace function public.issue_shop_qr_session(p_shop_id uuid)
returns jsonb language sql security invoker set search_path=public,pg_temp
as $$ select private.apnaloop_issue_shop_qr_session(p_shop_id); $$;
create or replace function public.claim_shop_stamp(p_shop_id uuid,p_qr_token text,p_idempotency_key uuid)
returns jsonb language sql security invoker set search_path=public,pg_temp
as $$ select private.apnaloop_claim_shop_stamp(p_shop_id,p_qr_token,p_idempotency_key); $$;
create or replace function public.get_customer_loyalty(p_shop_id uuid)
returns jsonb language sql security invoker set search_path=public,pg_temp
as $$ select private.apnaloop_get_customer_loyalty(p_shop_id); $$;
create or replace function public.get_shop_dashboard(p_shop_id uuid)
returns jsonb language sql security invoker set search_path=public,pg_temp
as $$ select private.apnaloop_get_shop_dashboard(p_shop_id); $$;
create or replace function public.redeem_customer_reward(p_shop_id uuid,p_code text)
returns jsonb language sql security invoker set search_path=public,pg_temp
as $$ select private.apnaloop_redeem_customer_reward(p_shop_id,p_code); $$;
revoke all on function public.issue_shop_qr_session(uuid) from public,anon;
revoke all on function public.claim_shop_stamp(uuid,text,uuid) from public,anon;
revoke all on function public.get_customer_loyalty(uuid) from public,anon;
revoke all on function public.get_shop_dashboard(uuid) from public,anon;
revoke all on function public.redeem_customer_reward(uuid,text) from public,anon;
grant execute on function public.issue_shop_qr_session(uuid) to authenticated;
grant execute on function public.claim_shop_stamp(uuid,text,uuid) to authenticated;
grant execute on function public.get_customer_loyalty(uuid) to authenticated;
grant execute on function public.get_shop_dashboard(uuid) to authenticated;
grant execute on function public.redeem_customer_reward(uuid,text) to authenticated;
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='stamp_events') then
      alter publication supabase_realtime add table public.stamp_events;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='reward_redemptions') then
      alter publication supabase_realtime add table public.reward_redemptions;
    end if;
  end if;
end $$;

