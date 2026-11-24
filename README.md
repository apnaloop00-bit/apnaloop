# ApnaLoop

QR stamp loyalty for Indian small shops — **Purane customers wapas lao.**

## Repository layout
- `prototype/index.html` — original uploaded single-file prototype, preserved for iterative refactoring.
- `docs/production-audit.md` — infrastructure and production-readiness audit.
- `supabase/migrations/` — database migration history mirrored from the existing Supabase project.

## Existing infrastructure
- GitHub: `apnaloop00-bit/apnaloop`
- Supabase: project `apnaloop-live` (Mumbai)
- Vercel: existing project `apnaloop`

## Current status
The prototype is not production-ready yet. It currently includes browser-generated OTP, seeded demo state and localStorage persistence. The Supabase schema exists, but the original UI does not yet use it for real application reads/writes. See [production audit](docs/production-audit.md).

Development work is isolated on `feat/supabase-live-foundation`; the existing `main` branch is preserved.
