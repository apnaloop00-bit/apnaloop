-- Production FK indexes and shop visibility policy cleanup.
-- Applied to Supabase project aebdkkczseaytavprnjo on 2026-11-24.

create index if not exists audit_logs_actor_user_id_idx on public.audit_logs(actor_user_id);
create index if not exists fraud_logs_customer_user_id_idx on public.fraud_logs(customer_user_id);
create index if not exists otp_verifications_user_id_idx on public.otp_verifications(user_id);
create index if not exists reward_redemptions_customer_user_id_idx on public.reward_redemptions(customer_user_id);
create index if not exists reward_redemptions_redeemed_by_idx on public.reward_redemptions(redeemed_by);
create index if not exists reward_redemptions_shop_id_idx on public.reward_redemptions(shop_id);
create index if not exists stamp_events_customer_user_id_idx on public.stamp_events(customer_user_id);
create index if not exists stamp_events_issued_by_idx on public.stamp_events(issued_by);
create index if not exists stamp_events_shop_id_idx on public.stamp_events(shop_id);
create index if not exists stamps_issued_by_idx on public.stamps(issued_by);
create index if not exists stamps_loyalty_card_id_idx on public.stamps(loyalty_card_id);
create index if not exists whatsapp_messages_shop_id_idx on public.whatsapp_messages(shop_id);

drop index if exists public.stamps_one_per_shop_customer_day;

drop policy if exists "Anyone can view active shop public profiles" on public.shops;
drop policy if exists "Owners can view their own shops" on public.shops;
create policy shops_select_public_or_owner
on public.shops
for select
to anon, authenticated
using (is_active = true or owner_user_id = (select auth.uid()));
