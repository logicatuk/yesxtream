# CLAUDE.md — Yesstream Activation Platform (master context)

> Read this file first in every session. Then read only the docs listed in "Where to look".
> This file is also valid as `AGENTS.md` (Codex, Cursor, others). Copy it under that name if your tool expects it.

## 1. What we are building

A SaaS **activation and management platform** for an IPTV player called **Yesstream**.

- The **Flutter player app already exists** (cross-platform: Android, Android TV, macOS, Linux, Windows; open source, Apache-2.0). **Do not rebuild it.** Only make the small changes listed in `docs/06-FLUTTER-INTEGRATION.md`.
- We build: **(a)** a backend API, **(b)** a web panel for 4 roles, **(c)** documentation and tests.
- The player gives a **7-day free trial**. After that it is locked until activated.
- Activation happens from: our website (customer pays), a **reseller**, or a **sub-reseller** (both spend credits).

## 2. Business rules (never break these)

| Rule | Value |
|---|---|
| Free trial | 7 days from first device registration |
| Plan YEAR_1 | costs **1 credit** |
| Plan FOREVER (lifetime) | costs **2.5 credits** |
| Credit storage | integers, **1 credit = 1000 units** (YEAR_1 = 1000, FOREVER = 2500). Show "2.5" only in the UI |
| Super admin credits | unlimited (no balance stored, spending always allowed, still logged) |
| Customer login | **MAC + 6-digit device key** (shown in the app). MAC alone is never enough |
| Sub-reseller depth | maximum 2 levels below super admin: reseller → sub-reseller. No third tier |
| Price | always decided by the server. The client never sends a price |

## 3. Roles

1. **Super admin** (the owner) — manages everything.
2. **Reseller** — manages own customers/devices, spends credits, buys credits, creates sub-resellers.
3. **Sub-reseller** — same panel as reseller, restricted (no own sub-resellers unless parent enables the toggle, cannot buy credits, only receives credits from parent).
4. **Customer (end user)** — activates own device, manages own playlist, views own device.

## 4. Stack

- API: **NestJS + TypeScript**
- Panel: **Next.js + React + TypeScript**
- DB: **PostgreSQL** (source of truth for licenses and money)
- Cache/queues/rate limits: **Redis**
- Files: **Cloudflare R2** (S3-compatible)
- Docs: **OpenAPI + Swagger UI**
- Realtime: WebSocket gateway + polling fallback

## 5. Engineering rules

1. **Credits are an append-only ledger.** Never edit a balance. Corrections are new entries.
2. **Activation = one atomic DB transaction**: lock wallet + license, recheck balance and eligibility, write ledger entry + license event + config version bump + outbox event. All or nothing.
3. **Idempotency-Key header** on every money or activation request. Same key + same body returns the original result. Same key + different body returns an error.
4. **Tenant isolation**: every query is filtered by the caller's organization tree. A reseller never sees another tree. Foreign IDs return "not found", never "forbidden".
5. **Five separate auth types**: panel user, customer, device, reseller API key, payment webhook. Never mix them.
6. **Playlist credentials are encrypted at rest** and **never returned in full** to the panel (redact).
7. **Hiding a button is not security.** Every endpoint checks role, scope and ownership.
8. **Events are notifications, not grants.** The app receives "something changed", then fetches current state from the API.
9. Server-side pagination everywhere. No unbounded lists.
10. A payment return URL never marks an order as paid. Only a verified signed webhook does.
11. No secrets in code, logs, errors or Swagger examples. Use fake data.
12. UI: every screen has loading, empty, error, permission-denied states; confirm dialogs for money actions; double-click protection.

## 6. How to work (process rules for the AI)

- Work on **one task at a time**, the one I give you.
- Before coding: state your plan in a few lines. After coding: list files changed and how to test.
- Ask me before: deleting data, changing the database design, adding a dependency, or choosing a payment gateway.
- If a requirement is unclear, ask **one** question, then proceed.
- Do **not** invent features I did not request.
- Write tests with each feature (not at the end).
- Never touch the player's playback engine.

## 6b. Open decisions (ask before building the related part)

- Payment gateway: not chosen yet.
- Credit pack prices: not defined yet.
- Hosting provider: not chosen yet.

## 7. Where to look

| Need | File |
|---|---|
| Product behavior, panel screens | `docs/01-PRODUCT.md` |
| Architecture, auth, security, workflows | `docs/02-ARCHITECTURE.md` |
| Database tables and relations | `docs/03-DATABASE.md` |
| API routes and conventions | `docs/04-API.md` |
| Build order, one prompt per step | `docs/05-PROMPTS.md` |
| Changes needed in the Flutter app | `docs/06-FLUTTER-INTEGRATION.md` |
