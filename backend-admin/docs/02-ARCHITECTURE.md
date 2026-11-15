# 02 — Architecture, security and critical workflows

## 1. System overview

```
Next.js panel (super admin / reseller / sub-reseller / customer areas)
        |  HTTPS, cookies + CSRF
        v
NestJS API  <-- HTTPS (device credential) -- Flutter app (Yesstream)
   |   \-- WebSocket gateway (device channel)
   |-- PostgreSQL (licenses, ledger, config: source of truth)
   |-- Redis (rate limits, queues, locks, cache)
   |-- Workers (outbox delivery, emails, expiry reminders, bulk jobs)
   |-- Cloudflare R2 (app binaries, logos, ticket images)
   |-- Payment adapter (gateway TBD) + Email adapter
```

Suggested monorepo:
```
/apps/api        NestJS
/apps/panel      Next.js
/packages/shared types, enums, constants (plans, statuses, error codes)
/infra           docker-compose, env templates
/docs
```

## 2. Five authentication audiences (never mixed)

| Audience | Used by | Credential | Notes |
|---|---|---|---|
| Panel user | super admin, reseller, sub-reseller | username/email + password, optional 2FA | Session cookie (httpOnly, secure, SameSite) + CSRF token, refresh rotation |
| Customer | end user | MAC + 6-digit device key | Short session bound to one device; rate limit + lockout; key can be regenerated from the app |
| Device | the Flutter app | device credential issued at registration | Used for heartbeat, configuration, entitlement, updates, WebSocket |
| API key | reseller external integrations | `Authorization: ApiKey <key>` | Stored hashed, scoped, rotatable, 60 req/min, no user privileges |
| Webhook | payment gateway | signature header | Raw-body signature check, event inbox with dedupe |

## 3. Authorization model

- Roles: `SUPER_ADMIN`, `RESELLER`, `SUB_RESELLER`, `CUSTOMER`.
- Organization tree: super admin org → reseller orgs → sub-reseller orgs (depth max 2).
- **Scope rule**: a panel user can read/write only data whose `organization_id` is their own org or a descendant they are allowed to see. Parent sees child summaries and credit movements, never the child's customers' playlist credentials.
- Every service method receives `(principal, resourceId)` and verifies ownership. Controllers never trust IDs from the client.
- Foreign resources return `404`.
- Sensitive actions (credit adjustment, revoke license, reseller suspension) require a reason and are audited.

## 4. Credit and license accounting

### Ledger
- `wallets`: one per organization. Super admin wallet is flagged `unlimited`.
- `ledger_entries`: immutable. Fields: wallet, type (GRANT, PURCHASE, TRANSFER_IN, TRANSFER_OUT, ACTIVATION_SPEND, ADJUSTMENT, REFUND_REVERSAL), signed amount in units, balance_after, reference (order/activation/transfer), reason, actor, created_at.
- Balance = sum of entries (kept as a cached projection updated in the same transaction).
- Corrections add a reversing entry linked to the original.

### Activation (atomic)
```
Select device -> verify authorization -> server resolves plan/cost/expiry -> confirm
-> POST /activations with Idempotency-Key
-> BEGIN; lock license row + wallet row
-> recheck eligibility (not FOREVER, not suspended, plan valid) and balance
-> insert ledger entry (negative), license event, update license projection,
   increment device configVersion, insert outbox event
-> COMMIT -> respond with committed result
-> worker pushes `license.changed` to the app
```
Failure at any step leaves no debit and no license change.

### Credit transfer
Parent selects a direct child -> server verifies relationship and entitlement -> shows resulting balances -> confirm -> lock both wallets in a fixed order -> two balanced ledger entries -> commit. Transfers create no new credits. A failed transfer leaves both wallets unchanged.

### Transfer activation to another device
Verify caller owns the old device -> verify target installation exists and is not FOREVER-active -> keep paid expiry -> bind license to the new device -> revoke the old device's credentials/lease -> increment license epoch -> record license event. Offline leases may remain valid until their short expiry (do not promise instant offline revocation). Transfer never moves credits.

### Purchase and fulfillment
```
Quote -> order -> checkout -> browser shows "pending"
-> signed webhook arrives -> store in inbox (dedupe by provider event id)
-> validate order, merchant, amount, currency -> fulfill exactly once
-> credit the wallet (reseller pack) or activate license (customer purchase)
-> notify
```
Duplicate events and multiple successful attempts must never produce duplicate credits or licenses.

## 5. Playlists and configuration

- Input types: M3U URL or Xtream `host|username|password`. Max 5 per device.
- Credentials encrypted at rest (envelope encryption, key from environment/KMS). Panel responses show redacted values (e.g. host + `***`).
- Device configuration endpoint returns decrypted data **only** to the authenticated device.
- Each committed change increments `config_version`. Updates use optimistic locking (`version` / `If-Match`); stale edits get `409 VERSION_CONFLICT`.
- Playlist test: server-side fetch with SSRF protection (block private IP ranges, redirects limited, timeouts, size limits).
- Ownership of playlists: playlists added by a reseller are tagged with that reseller's org. A reseller can delete only their own. Customer-added playlists belong to the customer. If the device is activated by a reseller, the reseller's list replaces the device lists (per HotPlayer behavior); otherwise it only replaces its own.

## 6. Mass host change

1. Preview request: oldHost, newHost, optional port, optional scheme, scope = caller's own playlists.
2. Server parses every playlist URL (Xtream and M3U), matches host **exactly** (case-insensitive), applies port and scheme rules, returns the list of affected playlists with redacted before/after and a job id.
3. Apply: job runs in a worker, per-item result (success/skipped/failed), each success bumps device config version and outbox event.
4. Rollback: restores previous encrypted values stored in the job.

## 7. Realtime

- WebSocket channel is chosen from the **authenticated device identity**, never from a client-supplied device ID.
- Events: `device.configuration.changed`, `license.changed`. At-least-once, may reorder. The app compares versions and refetches.
- Outbox pattern: events written in the same transaction as the business change; a worker delivers and retries; consumers dedupe.

## 8. Security checklist

- Secure first-admin bootstrap command; no default production password.
- Passwords hashed (argon2/bcrypt), 12+ chars for created accounts.
- Rate limits, independently for: login, customer login, MAC lookups, check-device, pairing, API keys.
- Hashed API keys and session secrets. Integration secrets are write-only.
- Redacted logs, audit and exports. No credential-bearing URLs in errors.
- Safe uploads: type and size checks (images up to 5 MB), random file names, private bucket + signed URLs.
- Runtime DB role separate from migration role.
- Audit record: actor, organization, subject, action, reason, request id, timestamp.
- Backups and restore tested.

## 9. Observability
Structured logs with `requestId`, health and readiness endpoints, job dashboard, alerts on failed outbox/webhook processing.

## 10. Error format
`application/problem+json` with `type`, `title`, `status`, `code`, `detail`, `requestId`.
Required codes: `INSUFFICIENT_CREDITS`, `DEVICE_PROOF_REQUIRED`, `COOLDOWN_ACTIVE`, `QUOTE_EXPIRED`, `VERSION_CONFLICT`, `IDEMPOTENCY_MISMATCH`, `PROVIDER_UNAVAILABLE`, `ALREADY_LIFETIME`, `MAC_NOT_FOUND`, `NOT_ENOUGH_ROOM`.
