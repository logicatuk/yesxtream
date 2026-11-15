# 04 — API specification

## 1. Conventions

- Base path: `/v1`
- JSON fields: camelCase. Dates: UTC RFC3339 in the panel API. (The public reseller API uses Unix milliseconds to match the HotPlayer style.)
- Money: integer minor units + currency. Credits: integer units, serialized as decimal strings (`"2500"`).
- Pagination: cursor or page/limit. Default 25, max 100.
- Resource updates: `version` / `If-Match`; stale returns `409 VERSION_CONFLICT`.
- Money and activation requests require `Idempotency-Key`.
- Errors: `application/problem+json` with `code` and `requestId`.
- OpenAPI operation IDs, tags, roles, auth audience and examples are required for every route (see Swagger rules at the end).

## 2. Panel API (cookie session)

### Auth and account
```
POST   /auth/login
POST   /auth/mfa/verify
POST   /auth/refresh
POST   /auth/logout
POST   /auth/password/forgot
POST   /auth/password/reset
GET    /auth/sessions
DELETE /auth/sessions/{id}
GET    /me
PATCH  /me
POST   /me/password           (current, new, repeat)
POST   /me/mfa/enroll
POST   /me/mfa/confirm
```

### Organizations
```
GET    /organizations                 (admin: all; reseller: own children)
POST   /organizations                 (admin creates reseller; reseller creates sub-reseller)
GET    /organizations/{id}
PATCH  /organizations/{id}            (name, canCreateChildren, status)
POST   /organizations/{id}/suspend
POST   /organizations/{id}/enable
GET    /organizations/{id}/store
PATCH  /organizations/{id}/store      (whatsapp, telegram, socials, logo)
POST   /assets/upload-intents         (signed R2 upload)
```
Create body for sub-reseller: `name`, `username`, `email`, `initialPassword` (min 12, letters + numbers), `canCreateChildren`.

### Devices
```
GET    /devices                       (filters: status, platform, expiryFrom/To, lastSeenFrom/To, version, q)
POST   /devices                       (add by MAC: { mac, customerName?, note? })
GET    /devices/{id}
PATCH  /devices/{id}                  (name, note, customer)
GET    /devices/{id}/activation-history
GET    /devices/{id}/version-history
POST   /devices/{id}/decommission
GET    /devices/check/{mac}           (Check MAC screen; same data as public check-device)
```

### Customers
```
GET    /customers
POST   /customers
GET    /customers/{id}
PATCH  /customers/{id}
```

### Licenses and activation
```
POST   /activations                   Idempotency-Key required
       body: { deviceId, plan: "YEAR_1" | "FOREVER", note?, extend? }
       -> { status, balanceUnits, license: { plan, expiresAt }, ledgerEntryId }
POST   /licenses/{id}/migrations      (transfer activation to another device)
       body: { targetDeviceId }
POST   /licenses/{id}/suspensions     (admin)
POST   /licenses/{id}/revocations     (admin)
GET    /licenses
GET    /licenses/{id}
GET    /licenses/{id}/events
```
Plan costs are resolved by the server: YEAR_1 = 1000 units, FOREVER = 2500 units. A preview endpoint returns cost, new expiry and "enough credits" per plan so the UI can show "Not enough credits":
```
GET    /devices/{id}/activation-options
       -> [{ plan, costUnits, newExpiresAt, canAfford, reasonIfNot }]
```

### Playlists
```
GET    /devices/{id}/playlists        (redacted)
POST   /devices/{id}/playlists        body: array or single { name?, url }   (url = M3U link or host|user|pass)
PATCH  /playlists/{id}                If-Match
DELETE /playlists/{id}
DELETE /devices/{id}/playlists        (delete the caller's playlists on this device)
POST   /playlists/{id}/validation     (test)
```
Max 5 playlists per device. Items without a url are skipped. Errors: `NOT_ENOUGH_ROOM`, `INVALID_PLAYLISTS`, `NAME_OR_URL_TOO_LONG`.

### Mass host change
```
POST   /jobs/host-change-previews     body: { oldHost, newHost, port?, scheme? }
GET    /jobs/{id}
POST   /jobs/{id}/apply
POST   /jobs/{id}/rollback
```

### Credits
```
GET    /wallets/me
GET    /wallets/{id}/entries          (filters: type, dateFrom, dateTo; paginated)
POST   /credit-transfers              Idempotency-Key; { toOrganizationId, amountUnits }
POST   /admin/credit-adjustments      Idempotency-Key; { organizationId, amountUnits, reason }  (admin)
GET    /credit-packs                  (published packs)
POST   /admin/credit-packs            (draft)
PATCH  /admin/credit-packs/{id}
POST   /admin/credit-packs/{id}/publish
```

### Orders and payments
```
POST   /quotes
POST   /orders
GET    /orders
GET    /orders/{id}
POST   /orders/{id}/checkout
POST   /webhooks/payments/{provider}   (public, signature required, raw body)
GET    /admin/payments
GET    /admin/reconciliation
POST   /orders/{id}/refund-requests    (phase 2)
```

### Support
```
GET    /tickets                        (own + from children + assigned to me)
POST   /tickets                        { subject, category, deviceMac?, message, attachmentKey? }
GET    /tickets/{id}
POST   /tickets/{id}/messages
PATCH  /tickets/{id}                   (status)
```

### Releases and downloads
```
GET    /downloads                      (cards for the download center)
GET    /releases
POST   /admin/releases
POST   /admin/releases/{id}/rollouts
POST   /admin/releases/{id}/halt
PUT    /admin/download-links/{id}
```

### API keys
```
GET    /api-keys
POST   /api-keys
DELETE /api-keys/{id}
POST   /api-keys/{id}/rotations
```

### Admin only
```
GET    /admin/overview
GET    /admin/settings
PATCH  /admin/settings
GET    /admin/integrations/{provider}
PUT    /admin/integrations/{provider}  (write-only secrets)
POST   /admin/integrations/{provider}/tests
GET    /audit-events
GET    /admin/jobs
POST   /admin/jobs/{id}/replay
POST   /exports
GET    /exports/{id}
```

### Dashboards
```
GET    /dashboard                      (role-scoped: counts, credits, recent activity; each figure has period + definition)
```

## 3. Customer API (customer session)
```
POST   /customer/login                 { mac, deviceKey }
POST   /customer/logout
GET    /customer/device
GET    /customer/playlists
POST   /customer/playlists
PATCH  /customer/playlists/{id}
DELETE /customer/playlists/{id}
GET    /customer/activation-options    (prices set by server)
POST   /customer/orders                (buy YEAR_1 or FOREVER)
GET    /customer/orders
POST   /customer/tickets
GET    /customer/tickets
POST   /customer/deletion-requests
GET    /customer/support-contacts      (reseller WhatsApp/Telegram)
```

## 4. Device API (device credential; used by the Flutter app)
```
POST   /devices/register               -> { deviceId, publicMac, deviceKey (6 digits, shown once), credential, trialEndsAt }
POST   /devices/{id}/session           (proof of possession, short-lived token)
POST   /device/heartbeat               { appVersion, platform, model, osVersion, capabilities }
GET    /device/entitlement             -> { status, plan, expiresAt, trialEndsAt, licenseEpoch, lease (signed, short) }
GET    /device/configuration           -> { configVersion, playlists[ decrypted ] }
GET    /device/updates?platform=&channel=&version=
WS     /device/events                  (channel from authenticated identity)
```
Events: `device.configuration.changed`, `license.changed` (payload carries only the new version numbers).
Rule: the app asks for **its own** data only. No device ID in the path for configuration/entitlement.

## 5. Public reseller API (API key) — HotPlayer-compatible

Base: `/api/v1/reseller` · Header: `Authorization: ApiKey YOUR_API_KEY` · Rate limit: 60/min, `429` with `Retry-After`.

```
GET    /balance
GET    /list-customers?status=all|active|expiring|expired&page=1&limit=100
GET    /check-device/{mac}
POST   /activate                       { mac, subscription: "YEAR_1"|"FOREVER", note?, extend? }
POST   /add-playlists/{mac}            [ { name?, url } ]  (max 5)
DELETE /delete-playlists/{mac}
```
Answer shape: `{ "status": "success", ... }` or `{ "status": "failed", "message": "..." }`.
Status codes: 200 success; 400 failed with message; 401 bad/missing key or disabled account (no body); 403 distributors only; 405 wrong method; 429 rate limit.
`list-customers` returns `mac`, `macs[]`, `system`, `plan`, `expiration` (Unix ms or null), `status` (active/expiring/expired), `note`, `activatedAt`, `lastConnection`. Oldest first. `total` for paging.
`check-device` returns `{ status, mac, expiration, plan }` where plan is `TRIAL`, `YEAR_1` or `FOREVER`.
Documented failure messages to reuse: "MAC is required", "MAC not found", "MAC already activated FOREVER", "MAC already activated, if you want to extend please provide \"extend\": true", "Balance insufficient", "Not enough room on the device: ...", "Invalid playlists: send a JSON array of {name, url}".
Playlist rule: on a device you activated, your list replaces all its playlists; on any other device it replaces only the playlists you added.

## 6. Swagger / OpenAPI requirements

- Swagger UI at `/docs`, JSON at `/openapi.json`, written guide at `/developer-guide`.
- Each operation: unique operationId, tag, purpose, allowed roles, auth audience, parameters, request/response schemas, error schemas with codes, pagination/filter/sort rules, idempotency and version preconditions, audit behavior, examples (fake data only).
- Sensitive fields marked write-only. Nullable and optional fields distinguished.
- Production exposure configurable; "Try it out" against safe sandbox only. CI checks the spec for drift.
