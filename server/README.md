# Perfect Nap — push relay (Vercel)

Tiny, stateless service that lets one parent's nap action update the **other** parent's lock-screen
Live Activity instantly, even when their app is closed. Apple only allows Live Activity updates via an
APNs push from a server that holds the APNs auth key — this is that server, and nothing more. It stores
no data.

Designed so a future `/api/nap-event` endpoint can also persist nap events (all-users training data) —
that's a deliberate phase 2 and needs a privacy-policy update first, since it's data collection.

## Deploy (git-connected)
1. Vercel → **Add New… → Project** → import the `marcushyett/perfect-nap` GitHub repo.
2. Set **Root Directory** to `server`.
3. Framework preset: **Other** (no build step — it's just serverless functions in `api/`).
4. Add the env vars below, then deploy. Pushes to `main` auto-deploy.

## Environment variables
| Name | Value |
|------|-------|
| `APNS_KEY_ID` | 10-char APNs auth key ID (from the .p8 you created) |
| `APNS_PRIVATE_KEY` | the full `.p8` file contents (PEM, `-----BEGIN PRIVATE KEY----- …`) |
| `APNS_TEAM_ID` | `9DG37ADF64` |
| `APNS_BUNDLE_ID` | `com.marcushyett.perfectnap` |
| `APNS_ENV` | `production` (TestFlight + App Store both use production APNs) |
| `RELAY_SHARED_SECRET` | a long random string; the app sends it as the `X-Relay-Secret` header |

## Endpoints
- `GET /api/health` → `{ ok, apnsConfigured, apnsEnv, hasSecret }` — verify the deploy + that env vars landed (no secrets returned).
- `POST /api/push` (header `X-Relay-Secret`) → forwards a Live Activity push to APNs.
  Body: `{ pushToken, pushToStart?, event?, contentState, attributes?, attributesType?, staleSeconds?, dismissSeconds?, alert? }`
  - **update** an existing Live Activity: `{ pushToken: <activity update token>, contentState: {…} }`
  - **start** one remotely: `{ pushToken: <push-to-start token>, pushToStart: true, attributesType: "NapActivityAttributes", attributes: {…}, contentState: {…} }`
