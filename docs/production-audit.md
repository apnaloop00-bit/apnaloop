# ApnaLoop production audit — 24 Nov 2026

## Existing services discovered
- GitHub repository: https://github.com/apnaloop00-bit/apnaloop (main branch retained; work isolated on `feat/supabase-live-foundation`).
- Supabase project: `apnaloop-live`, ref `aebdkkczseaytavprnjo`, Mumbai region.
- Vercel project: `apnaloop`, existing production deployment READY. Deployment protection currently requires Vercel SSO on deployment URLs.
- Vercel Git context currently reports no linked Git projects. Do not create a replacement Vercel project; connect the existing project to this repository through its Git settings after confirming the Git provider integration.

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
- Implement server-validated, transactional stamp issuance and reward redemption (including six-digit redemption codes and one-stamp-per-shop-per-India-day constraints).
- Add secure QR session issuance/verification, abuse throttling, and server-side geofence validation where applicable.
- Complete owner/customer/admin role model and review every RLS policy against actual app journeys.
- Add server-side Razorpay order/signature/webhook handling; ₹149 subscription and 30-day trial enforcement.
- Add WhatsApp Cloud API templates, consent handling, queue delivery and Sunday digest scheduler.
- Add PWA manifest, icons and service worker.
- Run the 15 end-to-end journeys and browser/mobile tests.
- Connect the existing Vercel project to GitHub. Do not expose secrets in client code; only the Supabase publishable key may be browser-visible.
- Confirm public production access intentionally; existing Vercel SSO protection is enabled on deployment URLs.

## Deployment rule
Do not deploy this prototype branch as a production application until authentication, data writes, RLS and reward/stamp server validation are implemented and tested. No fake “LIVE” status should be shown.
