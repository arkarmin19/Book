# BookFlow – Smart Appointment Booking and Management System

Multi-business appointment booking platform: customers book services with staff online; business owners manage services, staff, schedules and appointments.

**Stack:** Next.js 16 (App Router) · React · TypeScript · Tailwind CSS · shadcn/ui · React Hook Form · Zod · Supabase (PostgreSQL, Auth, Storage) · FullCalendar · Resend · Recharts · date-fns · Vitest · Playwright · Vercel

---

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| Node.js | 20.9+ (22 LTS recommended) | Next.js 16 minimum |
| npm | comes with Node | package manager |
| Docker Desktop | running | local Supabase stack |
| Git + GitHub account | — | version control |

---

## First-time setup (team lead does this once)

```bash
# 1. Create the Next.js app (accept defaults when asked)
npx create-next-app@latest bookflow --ts --tailwind --eslint --app --src-dir --import-alias "@/*" --use-npm --yes
cd bookflow

# 2. Initialise shadcn/ui (choose Radix + Neutral when prompted) and add base components
npx shadcn@latest init
npx shadcn@latest add button card input label textarea select dialog alert-dialog dropdown-menu badge skeleton separator avatar tabs sonner

# 3. Runtime dependencies
npm install @supabase/supabase-js @supabase/ssr zod react-hook-form @hookform/resolvers \
  date-fns @date-fns/tz server-only resend recharts \
  @fullcalendar/core @fullcalendar/react @fullcalendar/daygrid @fullcalendar/timegrid @fullcalendar/interaction

# 4. Dev dependencies
npm install -D supabase vitest @playwright/test prettier prettier-plugin-tailwindcss
npx playwright install chromium

# 5. Copy the Phase 1 files from this package into the project root (overwrite when asked)

# 6. npm scripts
npm pkg set scripts.typecheck="tsc --noEmit"
npm pkg set scripts.test="vitest run"
npm pkg set scripts.test:watch="vitest"
npm pkg set scripts.test:e2e="playwright test"
npm pkg set scripts.format="prettier --write ."
npm pkg set scripts.db:start="supabase start"
npm pkg set scripts.db:stop="supabase stop"
npm pkg set scripts.db:status="supabase status"
npm pkg set scripts.db:reset="supabase db reset"
npm pkg set scripts.db:types="supabase gen types typescript --local > src/types/database.types.ts"

# 7. Local Supabase
npx supabase init          # creates supabase/config.toml (say "N" to IDE settings if unsure)
npm run db:start           # first run downloads Docker images — takes a few minutes
npm run db:status          # shows API URL, publishable/anon key, secret/service_role key

# 8. Environment
cp .env.example .env.local # then paste the keys from db:status

# 9. Generate database types (empty schema for now; re-run after every migration)
mkdir -p src/types && npm run db:types

# 10. Verify
npm run lint && npm run typecheck && npm test && npm run dev
```

Then commit and push to a new **private** GitHub repo, and add your teammates as collaborators.

### Supabase Auth settings for local development

In `supabase/config.toml`, under `[auth]`:

```toml
site_url = "http://localhost:3000"
additional_redirect_urls = ["http://localhost:3000/auth/callback"]
```

Restart with `npm run db:stop && npm run db:start`.

---

## Setup for teammates (after the repo exists)

```bash
git clone <repo-url> && cd bookflow
npm ci
npx playwright install chromium
npm run db:start
cp .env.example .env.local   # paste keys from `npm run db:status`
npm run dev
```

---

## Scripts

| Script | Does |
|---|---|
| `npm run dev` | Start Next.js at http://localhost:3000 |
| `npm run build` / `npm start` | Production build / serve |
| `npm run lint` | ESLint |
| `npm run typecheck` | TypeScript, no emit |
| `npm test` | Vitest unit + integration tests |
| `npm run test:e2e` | Playwright end-to-end tests (starts dev server) |
| `npm run format` | Prettier |
| `npm run db:start` / `db:stop` / `db:status` | Local Supabase stack |
| `npm run db:reset` | Recreate local DB from migrations + seed |
| `npm run db:types` | Regenerate `src/types/database.types.ts` |

Local Supabase Studio (database UI): http://127.0.0.1:54323 · Local email inbox (Mailpit): http://127.0.0.1:54324

---

## Environment variables

| Variable | Exposed to browser? | Required from | Description |
|---|---|---|---|
| `NEXT_PUBLIC_SITE_URL` | yes | Phase 1 | App base URL |
| `NEXT_PUBLIC_SUPABASE_URL` | yes | Phase 1 | Supabase API URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | yes | Phase 1 | Publishable / anon key (safe: RLS protects data) |
| `SUPABASE_SECRET_KEY` | **no** | Phase 6 | Secret / service_role key — bypasses RLS |
| `RESEND_API_KEY` | **no** | Phase 11 | Resend API key |
| `EMAIL_FROM` | **no** | Phase 11 | Verified sender address |

Rules: never prefix a secret with `NEXT_PUBLIC_`; never commit `.env.local`; secret values only go in `.env.local` and Vercel project settings.

---

## Project structure

```
src/
  app/                 routes (pages + /api route handlers)
  components/ui/       shadcn/ui components (generated)
  components/…         booking, calendar, dashboard, forms, layout
  lib/env/             validated environment variables
  lib/supabase/        browser, server, proxy and admin clients
  lib/api/             API response envelope and helpers
  lib/validation/      Zod schemas shared by forms and API
  lib/time/            timezone and slot helpers
  server/services/     business logic used by route handlers
  server/notifications/ email sending + templates
  types/               generated database types, domain types
  proxy.ts             session refresh + route guard (Next.js 16)
supabase/migrations/   SQL migrations (Phase 2+)
tests/unit|integration|e2e
docs/                  project documentation
```

---

## Team workflow

- `main` is always deployable. Work on branches: `feat/booking-rpc`, `fix/calendar-tz`, `docs/erd`.
- Open a Pull Request; CI (lint, typecheck, tests, build) must pass; one teammate reviews.
- Commit messages: `feat: …`, `fix: …`, `docs: …`, `test: …`, `chore: …`.
- Database changes only via new migration files — never edit an applied migration.

Deployment instructions are added in Phase 13.
