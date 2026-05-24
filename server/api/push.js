import http2 from 'node:http2';
import crypto from 'node:crypto';

// Perfect Nap — ActivityKit push relay.
// Forwards a Live Activity push (start or update) to APNs so a partner's lock-screen Live Activity
// updates instantly even when their app is closed. Stateless: holds only the APNs key (env), stores
// nothing. The iOS app decides who/what to push (it reads the partner's token from the shared CloudKit
// zone) and calls this endpoint; this just signs the APNs request and forwards it.
//
// Required env vars (set in Vercel project settings):
//   APNS_KEY_ID        - 10-char APNs auth key ID
//   APNS_TEAM_ID       - Apple developer team id (9DG37ADF64)
//   APNS_BUNDLE_ID     - com.marcushyett.perfectnap
//   APNS_PRIVATE_KEY   - the .p8 contents (PEM). Newlines may be encoded as \n.
//   APNS_ENV           - "production" (TestFlight + App Store) or "sandbox"
//   RELAY_SHARED_SECRET- random string; the app sends it in the X-Relay-Secret header

const b64url = (buf) => Buffer.from(buf).toString('base64url');

let cachedJWT = null; // { jwt, iat } — APNs tokens are valid up to 60 min; we refresh well before.

function apnsJWT() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.iat < 1500) return cachedJWT.jwt;
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: process.env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: now }));
  const signingInput = `${header}.${claims}`;
  const key = crypto.createPrivateKey(process.env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n'));
  // ieee-p1363 → raw r||s signature (the JOSE/ES256 format APNs expects), not DER.
  const sig = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
  const jwt = `${signingInput}.${b64url(sig)}`;
  cachedJWT = { jwt, iat: now };
  return jwt;
}

function sendToAPNs({ host, path, headers, body }) {
  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${host}`);
    client.on('error', reject);
    const stream = client.request({ ':method': 'POST', ':path': path, ...headers });
    let data = '';
    let status = 0;
    stream.on('response', (h) => { status = h[':status']; });
    stream.setEncoding('utf8');
    stream.on('data', (c) => { data += c; });
    stream.on('end', () => { client.close(); resolve({ status, body: data }); });
    stream.on('error', (e) => { client.close(); reject(e); });
    stream.write(body);
    stream.end();
  });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!process.env.APNS_KEY_ID || !process.env.APNS_PRIVATE_KEY) {
    return res.status(503).json({ error: 'APNs not configured — set env vars' });
  }
  if ((req.headers['x-relay-secret'] || '') !== process.env.RELAY_SHARED_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const {
    pushToken,            // the recipient's Live Activity push token (update) or push-to-start token
    pushToStart = false,  // true → start a new Live Activity on the recipient (uses attributes)
    event,                // "start" | "update" | "end" (defaults from pushToStart)
    contentState,         // matches NapActivityAttributes.ContentState
    attributes,           // matches NapActivityAttributes (push-to-start only)
    attributesType,       // e.g. "NapActivityAttributes" (push-to-start only)
    staleSeconds,
    dismissSeconds,
    alert,
  } = req.body || {};

  if (!pushToken || !contentState) {
    return res.status(400).json({ error: 'pushToken and contentState are required' });
  }

  const now = Math.floor(Date.now() / 1000);
  const aps = {
    timestamp: now,
    event: event || (pushToStart ? 'start' : 'update'),
    'content-state': contentState,
  };
  if (staleSeconds) aps['stale-date'] = now + staleSeconds;
  if (dismissSeconds) aps['dismissal-date'] = now + dismissSeconds;
  if (alert) aps.alert = alert;
  if (pushToStart) {
    aps['attributes-type'] = attributesType;
    aps.attributes = attributes || {};
  }

  try {
    const result = await sendToAPNs({
      host: process.env.APNS_ENV === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com',
      path: `/3/device/${pushToken}`,
      headers: {
        authorization: `bearer ${apnsJWT()}`,
        'apns-topic': `${process.env.APNS_BUNDLE_ID}.push-type.liveactivity`,
        'apns-push-type': 'liveactivity',
        'apns-priority': '10',
      },
      body: JSON.stringify({ aps }),
    });
    return res.status(result.status === 200 ? 200 : 502).json({ apnsStatus: result.status, apnsBody: result.body });
  } catch (e) {
    return res.status(502).json({ error: String(e && e.message ? e.message : e) });
  }
}
