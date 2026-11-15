# 06 — Flutter app integration (Yesstream)

The player already exists (Flutter 3.29+, Riverpod, media_kit, Drift/SQLite, custom M3U/Xtream/XMLTV parsers, phased loading). Repo: github.com/clubanderson/Yesstream.

**Goal:** minimal, surgical changes so the app talks to our activation backend. Do not touch playback, EPG, Smart Channels or UI beyond what is listed.

**Licensing note:** the Yesstream repo is Apache-2.0. Check `LICENSE` and `NOTICE` and keep required attributions when you rebrand or monetize.

## 1. First step (P1 report)
Before coding, inspect and report: where providers and playlists live in Drift tables, where the app starts (`main.dart`, startup phases), where a global gate (lock screen) can wrap the home screen, existing settings screen, existing HTTP client, and how app version is read.

## 2. Changes needed

| # | Feature | Behavior |
|---|---|---|
| 1 | **Device identity** | On first launch create a stable device ID/MAC-style label (format `AA:BB:CC:DD:EE:FF`). Use the real MAC only if the platform allows it; otherwise generate and persist one. Store securely. |
| 2 | **Registration** | Call `POST /devices/register`. Receive device key (6 digits, shown once), device credential, trial end. Store credential in secure storage. |
| 3 | **Show MAC + key** | Settings and a license screen show MAC and the 6-digit key and the website address for activation. |
| 4 | **Trial and lock** | If status is TRIAL show remaining days. If EXPIRED/locked show a lock screen with MAC, key, website, reseller contact. Never block settings or the license screen. |
| 5 | **Entitlement** | `GET /device/entitlement` on start, resume, and every few minutes. Cache the signed lease for offline use with a bounded expiry (for example 72 hours). Verify the signature with a public key embedded in the app. |
| 6 | **Configuration** | `GET /device/configuration` returns playlists. Compare `configVersion` with the stored one; if newer, apply: add, replace or remove providers/playlists, then refresh channels. Mark server-managed playlists as locked in the UI. |
| 7 | **Realtime** | Open the WebSocket `/device/events`. On `device.configuration.changed` or `license.changed`, refetch. Always keep polling as fallback. Events never grant anything. |
| 8 | **Heartbeat** | `POST /device/heartbeat` with app version, platform, model, OS version, capabilities, at start and periodically. |
| 9 | **Update check** | `GET /device/updates?platform=&channel=&version=` and show an update prompt with the download link. |
| 10 | **Offline behavior** | No network: use cached lease and cached playlists. When the lease expires and there is no network, show a friendly "connect to verify" message. |

## 3. Rules
- The app talks only to the device API (`/device/*`), never to panel routes.
- Only HTTPS. Certificate validation on. No secrets in the app except the lease public key.
- Do not log playlist URLs or credentials.
- Do not trust events; verify by fetching.
- Version comparisons are per platform/channel, not a global string.
- Provider (IPTV) problems are shown separately from license problems.

## 4. Test plan (with the real app)
1. Fresh install: trial starts, MAC + key visible.
2. Reseller adds playlist: app updates without restart.
3. Reseller activates YEAR_1: lock screen disappears, expiry shown.
4. Reseller deletes playlists: app removes them.
5. Transfer activation: old device loses access after lease expiry or next check; new device active.
6. Airplane mode: cached lease works until expiry.
7. Wrong key on customer portal: locked out after attempts.
8. Mass host change: app receives new URLs.
