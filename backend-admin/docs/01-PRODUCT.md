# 01 — Product specification

## 1. Concept

Yesstream is an IPTV player. Our platform sells and manages **access to the player only**. We do not sell or host IPTV channels. The customer's IPTV provider subscription is separate: the player license can be valid while the provider subscription is expired, and the reverse.

## 2. Device lifecycle

```
First launch -> device registers -> gets MAC-style ID + 6-digit key -> TRIAL (7 days)
-> trial ends -> locked -> activation (YEAR_1 or FOREVER) -> ACTIVE
-> YEAR_1 expires -> EXPIRED -> renew (extend) or locked
```

Statuses: `TRIAL`, `ACTIVE`, `EXPIRING` (ends within 14 days), `EXPIRED`, `SUSPENDED`.
`FOREVER` never expires (expiration = null).

## 3. Plans and credits

| Plan | Credits | Units |
|---|---|---|
| YEAR_1 | 1 | 1000 |
| FOREVER | 2.5 | 2500 |

- Extending an active YEAR_1 device adds one more year on top of the current expiry.
- A FOREVER device cannot be activated again.
- Customers can also buy directly from the website (price set by super admin, paid through the gateway).

## 4. Super admin console

Menu: Overview, Resellers, Sub-resellers, Customers, Devices, Licenses, Credits, Orders & Payments, Credit Packs (pricing), Releases & Downloads, Support, Audit log, Jobs, Settings.

Capabilities:
- Create, suspend, enable resellers; set whether a reseller may create sub-resellers.
- Grant, remove, adjust credits (reason mandatory, shown in ledger).
- Define credit packs (name, credits, price, currency), draft then publish.
- Search any MAC; see full device and license history.
- Suspend or revoke a license.
- Publish app releases and download links per platform.
- Configure payment gateway (secrets are write-only).
- Answer all tickets.
- Global settings: trial length, plan costs, maintenance mode, support contacts.
- View audit log and failed background jobs, replay failed jobs.

Dashboard numbers must show their period and definition. Money and credits are never summed together.

## 5. Reseller panel (exact menu)

### 5.1 Overview
Credit balance, counts (active, expiring, expired, trial), recent activations, quick links.

### 5.2 Clients & devices
- Button **Add device**: enter a MAC like `46:20:15:B0:CF:59`. Optional customer name/note.
- Table columns: **Device, Owner, IP & network, Status, Access expires, Version, Last seen, Actions**.
- Filters: status, platform, expiry range, last-seen range, version. Search by MAC/owner/note. Server-side pagination.
- **Five action icons per row**:
  1. **Playlist** — add/edit/test/delete playlists (M3U link or Xtream `host|user|pass`), up to 5 per device.
  2. **Activate** — shows both plans with cost; shows "Not enough credits" on a plan if balance is too low; optional **Note**; confirm dialog with server-resolved cost and new expiry.
  3. **Details** — platform name, app version, last connection, subscription details, IP address, country flag, ISP/network, plus freshness of each field. Unknown values show "Unavailable".
  4. **Transfer activation** — move the activation to another device (target must be a verified installation; paid expiry preserved; old device loses access).
  5. **Delete playlists** — removes the playlists this reseller added.
- When the reseller saves a playlist, activates, transfers or deletes, the change is **pushed to the app automatically** (see push model below).

### 5.3 Credits & activity
Credit history (ledger: date, type, amount, balance after, reference), filters, export. **Buy credits**: list of packs from the super admin, checkout through the gateway. Show available balance (and reserved/debt if used) separately.

### 5.4 Sub-resellers
Create: Name, Username, Email, Initial password (at least 12 characters, letters and numbers). Info text: "Share this username and initial password with your partner. They sign in at the same reseller portal."
Toggle: **Allow this partner to create and manage their own team** (applies on save). Note: our baseline allows max 2 levels, so for a sub-reseller this toggle is **disabled and forced off** unless the super admin later approves a deeper tree.
Actions: transfer credits to a direct child, suspend/enable, view child's activity summary (never their customers' credentials).

### 5.5 Support inbox
- Receive tickets from sub-resellers and from the super admin.
- Create ticket: Subject, Category (e.g. Other), optional Device MAC, image attachment (max 5 MB), message thread, status (open, answered, closed).

### 5.6 Contacts & support
Reseller fills WhatsApp, Telegram, other social names. Shown to their customers (customer portal help page).

### 5.7 Account
Name, email, change password (current, new, repeat). Sessions list and logout of other sessions.

### 5.8 Mass host change
Fields: **Host to replace** (e.g. `old-host.com`), **New host** (e.g. `new-host.com`), optional **Port**, optional **http/https**.
Rules:
- Port: empty = every port changes. With a port (e.g. `example.com:8080`) only that port changes.
- Scheme: empty = every link changes and keeps its own scheme. With a scheme, only those links change (a link without a scheme counts as http). If the new host includes a scheme, it replaces the link's scheme.
- Button **Preview the change**: lists every affected playlist (device, old URL redacted, new URL redacted). Then **Apply**, with per-item results and **Rollback**.
- Only the reseller's own devices/playlists are touched. Exact host match, never substring.

### 5.9 Download center
One card per app with a CTA button: Android, iOS, macOS, Windows, Android TV, plus other stores: Huawei AppGallery and APKPure. Links managed by super admin (files in R2 or external store URLs).

### 5.10 Check MAC
Input a MAC. Result: known or not, TRIAL or ACTIVE or EXPIRED, plan, expiration, device type/platform, app version. Same data as the public reseller API `check-device`. No credit cost. Rate-limited.

## 6. Sub-reseller panel
Same screens as reseller, with: no third tier, no sibling/parent customer data, no credit checkout (credits come only from parent), no pricing/integration settings, no arbitrary credit issuance, no outbound credit transfer.

## 7. Customer portal (end user)

Login: **MAC + 6-digit device key** (shown in the app settings). Rate-limited with lockout. Session is limited to that device.

Screens:
- **My device**: status, plan, expiry, platform, app version, last connection.
- **Playlist**: add/edit/test/delete own playlists (unless a provisioner locked them; locked playlists show a lock icon).
- **Activate / Buy**: yearly or lifetime, price from server, checkout through gateway.
- **Orders**: purchase history.
- **Support**: open ticket, see replies; shows the reseller's contact info if the device was activated by a reseller.
- **Privacy**: request data export or deletion.

## 8. Push-to-app model

Each device has `configVersion` (integer). Any change to playlists, license or settings increments it.
1. Server commits the change and writes an outbox event.
2. Worker sends `device.configuration.changed` or `license.changed` over WebSocket to the authenticated device channel.
3. App receives it, calls `GET /device/configuration` and `GET /device/entitlement`, compares versions, applies.
4. Fallback: the app polls at startup, on resume, and every few minutes. Events can be lost or duplicated, so correctness never depends on them.

## 9. Notifications
In-panel notification center: ticket replies, low credits, devices expiring in 14 days, failed activation, credit received from parent.

## 10. Out of scope
Selling or hosting IPTV channels, relaying or transcoding streams, automatic commission payouts, rebuilding the player UI.
