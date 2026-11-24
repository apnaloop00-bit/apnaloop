# ApnaLoop production audit — 24 Nov 2026

## Existing services discovered
- GitHub repository: https://github.com/apnaloop00-bit/apnaloop (main branch retained; work isolated on `feat/supabase-live-foundation`).
- Supabase project: `apnaloop-live`, ref `aebdkkczseaytavprnjo`, Mumbai region.
- Vercel project: `apnaloop`, existing production deployment READY. Deployment protection currently requires Vercel SSO on deployment URLs.
- Existing Vercel project is now connected to this GitHub repository; automatic development-branch deployments are verified. Preview URLs still require Vercel SSO.

## Prototype audit
The uploaded HTML is preserved at `prototype/index.html`. It is a single-file Tailwind/Lucide/QRCode.js prototype. Its existing screens include customer registration/card, shop onboarding/dashboard, reward redemption, admin, WhatsApp drawer, QR standee and language switching.

The existing code is NOT production-safe:
- `createInitialState()` seeds sample shops, customers, stamps, WhatsApp messages and audit events.
- `loadState()` and `saveState()` use localStorage as the application data store.
- Customer OTP is generated in browser JavaScript and shown in a toast; it is not sent by an OTP provider.
- The “Supabase” modal only saves a URL/key and flips a local status flag; it does not perform Supabase reads/writes.
- Firebase is still the actual optional bridge and is unrelated to the configured Supabase database.
- Stamp uniqueness, QR token checks, geofence, reward codes and admin actions are browser-side and can be bypassed.
- No production PWA manifest/service worker was present in the inspected file.
- WhatsApp and Razorpay are UI/workflow placeholders until provider credentials and server-side webhooks are configured.

## Supabase state
The existing database already has RLS-enabled tables for profiles, customers/customer_profiles, shops/shop_owners, loyalty_cards, stamps/stamp_events, rewards, reward_redemptions, subscriptions, payments, whatsapp_messages, audit_logs, otp_verifications and fraud_logs. The existing business tables were empty at inspection time; no demo rows were imported.

Migrations recorded:
- `20261124173911_initial_loyalty_schema`
- `20261124181016_apnaloop_production_foundation`
- `20261124181129_security_policy_hardening`
- `20261124181825_production_fk_indexes_and_shop_policy`

Security posture:
- OTP verification rows are RLS-enabled with no client policies and direct anon/authenticated privileges revoked; this is intentionally service-only, but needs a documented server-side OTP flow.
- The Supabase security advisor currently reports only the informational OTP no-policy lint.
- Performance advisor no longer reports unindexed foreign keys or duplicate stamp-day indexes. It reports unused indexes (expected before application traffic).

## Work started
- Created branch `feat/supabase-live-foundation`; main has not been changed.
- Preserved the complete uploaded HTML in `prototype/index.html`.
- Applied and recorded the FK-index and shop SELECT policy cleanup migration above.

## Not yet production-ready
- Replace fake OTP with Supabase Phone Auth and a configured SMS provider.
- Replace localStorage state with authenticated Supabase reads and writes.
- Secure server-side QR stamp issuance, India-day duplicate protection, 10-stamp reward unlock and one-time six-digit redemption have been implemented and SQL integration-tested. Full browser/mobile E2E remains pending.
- QR sessions and redemption-code brute-force throttling are implemented; server-side geofence validation remains pending if required.
- Complete owner/customer/admin role model and review every RLS policy against actual app journeys.
- Add server-side Razorpay order/signature/webhook handling; ₹149 subscription and 30-day trial enforcement.
- Add WhatsApp Cloud API templates, consent handling, queue delivery and Sunday digest scheduler.
- Add PWA manifest, icons and service worker.
- Run the 15 end-to-end journeys and browser/mobile tests.
- Existing Vercel project is connected to GitHub. Do not expose secrets in client code; only the Supabase publishable key may be browser-visible.
- Confirm public production access intentionally; existing Vercel SSO protection is enabled on deployment URLs.

## Deployment rule
Do not deploy this prototype branch as a production application until authentication, data writes, RLS and reward/stamp server validation are implemented and tested. No fake “LIVE” status should be shown.


## Development milestone 1 — Supabase auth and shop onboarding (24 Nov 2026)
- Replaced demo-seeded initial state with empty production state. Business records are no longer loaded from localStorage.
- Replaced browser-generated OTP with Supabase Phone Auth `signInWithOtp` and `verifyOtp` calls.
- Added authenticated profile bootstrap for `profiles`, `customer_profiles`, and `customers` after a user is created.
- Added a Supabase-backed shop creation flow, owner mapping, reward template creation, and automatic 30-day trial subscription.
- Added `shops.phone_e164`; internal trigger functions have EXECUTE revoked from anon/authenticated roles.
- Removed the Firebase Firestore bridge and the fake "Supabase configured" behavior. Client writes that are not approved server transactions are disabled.
- Added empty-state screens when no shops are registered.
- Preserved the original UI and deployed the development branch to Vercel preview. Latest observed deployment: `apnaloop-odqonomql-apnaloop00-3988.vercel.app`, READY.
- Browser JavaScript syntax checked with Node `--check`.

## Remaining blockers for customer-ready use
- Supabase Phone Auth SMS provider and phone sign-in setting must be enabled/configured in the Supabase Auth dashboard. Until that is done, delivery of SMS OTP is not confirmed.
- The OTP flow has not been end-to-end tested with a real phone number.
- Stamp issuance, reward unlock/redemption, QR token validation, and dashboard history require server-side transactional functions. These are intentionally disabled rather than allowing insecure browser-only writes.
- Owner phone display and complete live dashboard datasets still need read-model/RPC implementation.
- Vercel preview remains protected by existing SSO; public access has not been enabled.
- Razorpay, WhatsApp Cloud API, PWA manifest/service worker and full E2E test suite remain outstanding.

## Latest security advisor
Privileged loyalty SECURITY DEFINER functions now live in the non-exposed `private` schema behind SECURITY INVOKER public RPCs. Remaining informational no-policy notices apply to internal-only tables (`customer_rewards`, `otp_verifications`, `qr_sessions`, `reward_claims`, `reward_redemption_attempts`) whose direct client privileges are revoked.


## Development milestone 2 — secure loyalty transactions (25 Nov 2026)
- Added 2-minute QR sessions using 256-bit random tokens; only a shop owner can issue one, and only its SHA-256 hash is stored.
- Added authenticated QR claim RPC with database row locking, idempotency, and one stamp per customer/shop/India day.
- Ten stamps atomically unlock a reward and reset the loyalty-card cycle.
- Reward code is six digits, expires in 30 days, and can be redeemed once by an authenticated shop owner.
- Added redemption guessing limit: 10 attempts per shop/owner per 15 minutes.
- Further stamps are blocked while an unlocked reward is pending.
- Added customer/shop dashboard RPCs and Realtime refresh events.
- Privileged SECURITY DEFINER implementations moved to the non-exposed private schema; public RPCs are SECURITY INVOKER wrappers.
- Internal QR/reward/attempt tables have RLS enabled and direct client table privileges revoked.

### Verification
SQL integration assertions passed for owner QR issuance, invalid QR rejection, 10th-stamp unlock, six-digit code, idempotent retry, customer reward read, owner-only dashboard, dashboard counts/activity, one-time redemption, duplicate-day rejection, pending-reward blocking and redemption rate limiting. Temporary test rows were cleaned; test shops/users/claims/sessions count is zero.
Supabase advisors show no unindexed foreign-key warnings and no public SECURITY DEFINER RPC warnings. Remaining no-policy notices are informational for internal-only tables with direct client privileges revoked. Remaining unused-index notices are for WhatsApp queue, OTP phone and shop phone indexes.

### Still pending before production
Real SMS provider configuration and mobile OTP delivery test; full browser/mobile E2E test; public Vercel access decision; geofence and stamp reversal workflows if required; WhatsApp Cloud API; Razorpay; PWA manifest/service worker; 15-journey acceptance testing. Existing Vercel preview remains SSO-protected.
