# 03 — Database design (plain language)
PostgreSQL login 

postgres://avnadmin:AVNS_UVDVU5XAw9VFcmoTG-T@pg-26a1f998-aessmaki-49ab.i.aivencloud.com:13527/defaultdb?sslmode=require

or 

Database name
defaultdb

Host
pg-26a1f998-aessmaki-49ab.i.aivencloud.com

Port
13527

User
avnadmin

Password
AVNS_UVDVU5XAw9VFcmoTG-T



SSL mode
require

General rules: PostgreSQL, UUID primary keys, UTC timestamps (`created_at`, `updated_at`), `version` integer on mutable rows (optimistic locking), indexes on every `organization_id`, ledger and license-event tables are append-only (no update/delete permission for the runtime role).

## Identity and tenancy

**users**: id, username (unique), email (unique), password_hash, role (SUPER_ADMIN / RESELLER / SUB_RESELLER), organization_id, status (active, suspended), mfa_secret (encrypted, nullable), last_login_at.

**organizations**: id, name, parent_id (nullable), level (0 admin, 1 reseller, 2 sub-reseller), status, can_create_children (bool), store_name, logo_url, whatsapp, telegram, other_socials (json of names only), created_by.

**sessions**: id, user_id, refresh_token_hash, user_agent, ip, expires_at, revoked_at.

**api_keys**: id, organization_id, name, key_hash, prefix, scopes, last_used_at, revoked_at.

**invitations** (optional, if email invites are added): id, organization_id, email, token_hash, expires_at, used_at.

## Customers and devices

**customers**: id, organization_id (the reseller who owns the record), name (nullable), email (nullable), note, created_at.

**devices**: id, public_mac (unique, normalized uppercase `AA:BB:CC:DD:EE:FF`), extra_macs (array, for TVs with wifi + ethernet), customer_id (nullable), owner_organization_id (nullable: the reseller who first attached/activated it), platform (ANDROID, ANDROID_TV, WEBOS, TIZEN, MACOS, WINDOWS, LINUX), model, os_version, app_version, config_version (int), status (derived and cached), registered_at, last_seen_at, last_ip, last_country, last_isp, last_asn, note, decommissioned_at.

**device_keys**: id, device_id, key_hash (6-digit key hashed), failed_attempts, locked_until, rotated_at. The plain key is only shown in the app.

**device_credentials**: id, device_id, secret_hash, issued_at, revoked_at, epoch (matches license epoch).

**device_attachments** (which organizations can see/manage a device): device_id, organization_id, reason (ACTIVATED, PLAYLIST_ADDED, ADDED_BY_MAC), created_at. This supports HotPlayer-style "devices you activated or touched".

**device_version_history**: device_id, app_version, observed_at.

## Licensing

**licenses**: id, device_id (unique while active), plan (TRIAL, YEAR_1, FOREVER), status (TRIAL, ACTIVE, EXPIRED, SUSPENDED, REVOKED), starts_at, expires_at (null for FOREVER), epoch, activated_by_org_id, last_activation_at, note.

**license_events** (immutable): id, license_id, device_id, type (TRIAL_STARTED, ACTIVATED, EXTENDED, TRANSFERRED_OUT, TRANSFERRED_IN, SUSPENDED, REVOKED, EXPIRED, CUSTOMER_PURCHASE), plan, from_expires_at, to_expires_at, actor_user_id, actor_org_id, ledger_entry_id (nullable), note, idempotency_key, created_at.

**activation_codes** (optional later): id, organization_id, plan, code_hash, status, redeemed_device_id.

## Money

**wallets**: id, organization_id (unique), balance_units (cached projection), unlimited (bool, true for super admin), updated_at.

**ledger_entries** (immutable): id, wallet_id, type, amount_units (signed), balance_after_units, reference_type, reference_id, related_entry_id (for reversals), reason, actor_user_id, idempotency_key, created_at.

**credit_packs**: id, name, credits_units, price_minor (integer cents), currency, status (draft, published, retired), version, sort_order.

**orders**: id, buyer_type (ORGANIZATION / CUSTOMER_DEVICE), organization_id or device_id, kind (CREDIT_PACK / DEVICE_PLAN), item_ref, amount_minor, currency, status (created, pending, paid, fulfilled, failed, refunded), idempotency_key.

**payment_attempts**: id, order_id, provider, provider_reference, status, amount_minor, currency, raw_event_ref.

**fulfillments**: id, order_id (unique), type, result_ref, created_at (unique order_id guarantees exactly-once).

**webhook_inbox**: id, provider, event_id (unique per provider), signature_valid, payload_redacted, processed_at, status.

**refunds** (phase 2): id, order_id, amount_minor, reason, status, reversal_entry_id.

## Playlists and configuration

**playlists**: id, device_id, organization_id (who added it, nullable if customer), added_by (RESELLER / CUSTOMER / BULK_JOB), name, type (M3U / XTREAM), host, credentials_encrypted, url_encrypted, locked (bool), position, version, created_at.

**bulk_jobs**: id, organization_id, type (HOST_CHANGE), params (old_host, new_host, port, scheme), status (previewed, running, done, failed, rolled_back), created_by.

**bulk_job_items**: id, job_id, playlist_id, before_encrypted, after_encrypted, result (pending, success, skipped, failed), error.

## Support

**tickets**: id, creator_user_id, creator_org_id, assignee_org_id (parent or admin), subject, category, device_mac (nullable), status, created_at.

**ticket_messages**: id, ticket_id, author_user_id, body, attachment_key (R2), created_at.

**notifications**: id, user_id, type, payload, read_at.

## Releases

**releases**: id, platform, channel (stable, beta), version, build, checksum, file_key (R2) or external_url, notes, rollout_percent, status (draft, published, halted), published_at.

**download_links**: id, platform, store (DIRECT, HUAWEI, APKPURE, PLAYSTORE, APPSTORE), label, url, sort_order, active.

## Platform

**settings**: key, value (trial_days, plan_year_units, plan_forever_units, maintenance_mode, support_contacts). Changes are audited.

**audit_log** (immutable): id, actor_user_id, actor_org_id, subject_type, subject_id, action, reason, request_id, ip, created_at, metadata (no secrets).

**outbox_events**: id, type, payload, status, attempts, available_at, created_at, processed_at.

**idempotency_keys**: key, scope, request_hash, response_snapshot, created_at, expires_at.

## Key relationships

```
organizations (tree) -> users
organizations -> customers -> devices -> playlists
devices -> licenses -> license_events
organizations -> wallets -> ledger_entries
orders -> payment_attempts ; orders -> fulfillments (one)
business transaction -> outbox_events -> worker -> WebSocket/email
```

## Required constraints
- One active license per device.
- `fulfillments.order_id` unique.
- `webhook_inbox (provider, event_id)` unique.
- `ledger_entries` and `license_events` and `audit_log`: no UPDATE/DELETE grants.
- Playlist count per device max 5 (enforced in service, double-checked by trigger or constraint).
- Normalized MAC format enforced.
