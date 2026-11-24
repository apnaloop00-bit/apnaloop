-- ApnaLoop auth profile bootstrap, shop ownership and 30-day trial automation.
-- Applied to project aebdkkczseaytavprnjo on 2026-11-24.

alter table public.shops add column if not exists phone_e164 text;

create or replace function public.apnaloop_handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  v_name := coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '');
  insert into public.profiles (id, full_name, phone_e164, preferred_language)
  values (new.id, nullif(v_name, ''), new.phone, 'hinglish')
  on conflict (id) do update set phone_e164 = excluded.phone_e164,
    full_name = coalesce(public.profiles.full_name, excluded.full_name), updated_at = now();
  insert into public.customer_profiles (user_id, display_name, phone_e164, preferred_language)
  values (new.id, nullif(v_name, ''), new.phone, 'hi')
  on conflict (user_id) do update set phone_e164 = excluded.phone_e164,
    display_name = coalesce(public.customer_profiles.display_name, excluded.display_name), updated_at = now();
  insert into public.customers (id, display_name, phone_e164)
  values (new.id, nullif(v_name, ''), new.phone)
  on conflict (id) do update set phone_e164 = excluded.phone_e164,
    display_name = coalesce(public.customers.display_name, excluded.display_name), updated_at = now();
  return new;
end; $$;

drop trigger if exists apnaloop_auth_user_created on auth.users;
create trigger apnaloop_auth_user_created after insert on auth.users
for each row execute function public.apnaloop_handle_new_auth_user();

create or replace function public.apnaloop_after_shop_created()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.shop_owners (shop_id, user_id)
  values (new.id, new.owner_user_id) on conflict (shop_id, user_id) do nothing;
  insert into public.subscriptions (shop_id, status, trial_starts_at, trial_ends_at)
  values (new.id, 'trialing', now(), now() + interval '30 days');
  return new;
end; $$;

drop trigger if exists apnaloop_shop_created_bootstrap on public.shops;
create trigger apnaloop_shop_created_bootstrap after insert on public.shops
for each row execute function public.apnaloop_after_shop_created();

create index if not exists shops_phone_e164_idx on public.shops(phone_e164);

-- Trigger functions are internal only; triggers continue to invoke them.
revoke all on function public.apnaloop_after_shop_created() from public, anon, authenticated;
revoke all on function public.apnaloop_handle_new_auth_user() from public, anon, authenticated;
