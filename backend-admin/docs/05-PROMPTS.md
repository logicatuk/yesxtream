# 05 — Build prompts (give them one at a time)

How to use:
1. Put `CLAUDE.md` (or `AGENTS.md`) and the `docs/` folder at the root of the project repository, next to a copy of the Yesstream Flutter code (or in a separate backend repo, with the Flutter repo linked).
2. Start every new AI session with: **"Read CLAUDE.md, then do the task below."**
3. Give **one prompt at a time**. Do not continue until the "Done when" checks pass.
4. Commit to Git after each prompt. If something breaks, revert and retry with the error message.

---

## P1 — Inspect the Flutter app (read-only)
```
Read CLAUDE.md and docs/06-FLUTTER-INTEGRATION.md. Then read the Yesstream Flutter repository without changing anything.
Report: how providers/playlists (M3U, Xtream) are stored; whether any device ID, login or license logic exists; where a trial timer and lock screen would go; where network calls happen; how the app could receive a "config changed" event; how the app is versioned.
Finish with the exact list of files to change, a risk list, and questions for me. Wait for my approval.
```
Done when: you have a written report and approved the change list.

## P2 — Project setup
```
Read CLAUDE.md and docs/02-ARCHITECTURE.md section 1. Create the monorepo (apps/api NestJS, apps/panel Next.js, packages/shared), docker-compose for PostgreSQL and Redis, env templates, linting, formatting, migration tooling, a health endpoint, and a README with local setup. No business features.
```
Done when: `docker compose up` works, API health returns OK, panel shows a blank page.

## P3 — Database
```
Read docs/03-DATABASE.md. First, give me a short entity-relationship summary and list anything you would change. Wait for approval. Then create migrations, enums, constraints, indexes, and a separate runtime DB role without UPDATE/DELETE on ledger_entries, license_events and audit_log. Add seed data for development only (fake data).
```
Done when: migrations run and roll back cleanly; append-only tables reject updates.

## P4 — Authentication and roles
```
Read docs/02-ARCHITECTURE.md sections 2 and 3, docs/04-API.md auth routes. Implement panel login, refresh, logout, forgot/reset password, change password, sessions, rate limiting, optional 2FA, role guards (SUPER_ADMIN, RESELLER, SUB_RESELLER), and a secure first-admin bootstrap command (no default password). Cookies httpOnly + CSRF.
Tests: each role is blocked from the others' routes; brute force is rate limited.
```

## P5 — Organizations and sub-resellers
```
Read docs/01-PRODUCT.md sections 4-6, docs/04-API.md organizations. Implement admin creating resellers; reseller creating sub-resellers (name, username, email, initial password 12+ chars with letters and numbers, canCreateChildren toggle). Reject a third tier. Suspend/enable. Store info (WhatsApp, Telegram, socials).
Tests: tree isolation; sub-reseller cannot create children.
```

## P6 — Wallets and ledger
```
Read docs/02-ARCHITECTURE.md section 4 and docs/03-DATABASE.md money tables. Implement wallets, append-only ledger, admin grant/remove/adjust (reason required, audited), parent-to-direct-child transfer in one transaction with both wallets locked in fixed order, history endpoint with filters and pagination. Super admin wallet is unlimited.
Tests: failed transfer changes nothing; concurrent spending cannot overdraw; corrections append reversing entries.
```

## P7 — Devices and customers
```
Read docs/01-PRODUCT.md section 5.2 and docs/04-API.md devices. Implement device registration (public MAC + 6-digit key hashed, device credential), reseller "add device by MAC", device list with server-side pagination/search/filters, device details (platform, version, last connection, subscription, IP, country, ISP with freshness), device attachments, rename/note, decommission. Rate-limit MAC lookups. MAC alone never grants access. Foreign devices return 404.
```

## P8 — Trial and activation
```
Read docs/02-ARCHITECTURE.md section 4 and docs/04-API.md licenses. Implement the 7-day trial, activation options endpoint (cost, new expiry, canAfford), POST /activations (YEAR_1 = 1000 units, FOREVER = 2500 units, optional note, extend) as ONE atomic transaction with Idempotency-Key, and license migration to another device. Reject lifetime-as-yearly and double lifetime. Super admin activations are free but logged.
Tests: insufficient credits (no debit, no license); concurrent spend on one credit (exactly one wins); lost response retry returns the original result; same key different body is rejected; migration blocks the old device.
```

## P9 — Playlists and push to app
```
Read docs/02-ARCHITECTURE.md sections 5 and 7, docs/04-API.md playlists and device API. Implement playlist add/edit/delete/test (M3U or Xtream host|user|pass, max 5, encrypted at rest, redacted in panel), config_version bump on every change, optimistic locking, SSRF-safe test fetch, outbox events, WebSocket gateway (channel from authenticated device only), device endpoints /device/configuration and /device/entitlement, and polling fallback. Follow the replace rules: activated-by-me devices replace all, others replace only mine.
Tests: stale edit gets 409; device cannot read another device's config; events are not required for correctness.
```

## P10 — Mass host change
```
Read docs/01-PRODUCT.md section 5.8 and docs/02-ARCHITECTURE.md section 6. Implement preview, apply (worker), per-item results, rollback. Exact host match; port and scheme rules exactly as written. Only the caller's own playlists.
Tests: no port = all ports; port given = only that port; scheme rules; foreign playlists untouched.
```

## P11 — Reseller panel UI (build in small steps, approve each)
```
Read docs/01-PRODUCT.md section 5 and 6. Build the Next.js reseller panel shell (sidebar, header with credit balance, notification center, responsive). Then ONLY: Overview. Stop and wait.
(Then in separate messages: Clients & devices table + five action icons; Credits & activity; Sub-resellers; Support inbox; Contacts & support; Account; Mass host change; Download center; Check MAC.)
Every screen: loading, empty, error, permission-denied states; confirm dialogs for money actions; double-submit protection; server-confirmed success only.
```

## P12 — Super admin console
```
Read docs/01-PRODUCT.md section 4. Build the console one module at a time: Overview, Resellers, Customers/Devices (global MAC search), Licenses, Credits, Credit Packs, Orders & Payments, Releases & Downloads, Support, Audit, Jobs, Settings. Every control calls a real API. Stop after each module.
```

## P13 — Customer portal
```
Read docs/01-PRODUCT.md section 7 and docs/04-API.md customer API. Build MAC + 6-digit key login (rate limit + lockout), device status, playlists, buy yearly/lifetime, orders, tickets, reseller contacts, privacy requests. Clear messages for trial, active, expired.
```

## P14 — Payments (ask me which gateway first)
```
Ask me which payment gateway to use. Then read docs/02-ARCHITECTURE.md "Purchase and fulfillment". Implement credit packs (reseller purchase) and direct customer purchase through one adapter: quote, order, checkout, signed raw-body webhook, inbox with dedupe, validation of order/amount/currency, exactly-once fulfillment. A return URL never marks an order paid. Sandbox only until I approve.
Tests: duplicate webhook = one fulfillment; two successful attempts = one fulfillment + flagged for refund.
```

## P15 — Support tickets
```
Implement tickets (subject, category, optional MAC, image up to 5 MB to private R2 with signed URLs, messages, status) between reseller, sub-reseller and admin, plus notifications. Safe upload checks.
```

## P16 — Releases and download center
```
Implement releases per platform/channel (version, checksum, R2 file or external URL, rollout, halt), download links for Android, iOS, macOS, Windows, Android TV, Huawei, APKPure, the reseller Download center cards, and the app update-check endpoint.
```

## P17 — Reseller API keys and public API
```
Read docs/04-API.md section 5. Implement scoped hashed API keys (create, rotate, revoke) and the HotPlayer-compatible /api/v1/reseller endpoints exactly as documented, including error messages and 60/min rate limit. Keys never inherit user privileges.
```

## P18 — Flutter app integration
```
Read docs/06-FLUTTER-INTEGRATION.md and my approved P1 report. Modify the Flutter app: device registration, show MAC + 6-digit key, 7-day trial and lock screen, entitlement fetch with signed offline lease, configuration fetch and apply, WebSocket events + polling fallback, heartbeat, update check. Do not touch the playback engine or unrelated UI.
Test with the real app against the dev backend.
```

## P19 — Swagger and documentation
```
Generate complete OpenAPI + Swagger UI per docs/04-API.md section 6. Write developer-guide chapters for: auth, roles, pairing/registration, playlists, activation, credits, orders/webhooks, migration, app integration, events, errors, idempotency, API keys. Add an importable API client collection and CI contract check.
```

## P20 — Security and test pass
```
Run and fix: tenant isolation tests, concurrent spend, idempotent retries, duplicate webhooks, stale edits, migration revocation, rate limits, encrypted credentials, redacted logs. Do a security review and report every failure and fix.
```

## P21 — Deployment
```
Prepare production deployment: environment variable reference (no secrets), DB backup/restore, rollback steps, process management, monitoring and alerts, go-live checklist. Ask me which hosting provider first.
```

---

## Final demo checklist
Admin creates reseller → reseller creates sub-reseller → admin funds reseller (audited) → reseller transfers credits → sub-reseller adds a customer device (real app) → adds playlist → activates YEAR_1 → app receives playlist and entitlement → ledger and audit match → an unrelated reseller cannot see any of it.
