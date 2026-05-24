import http2 from 'node:http2';
import crypto from 'node:crypto';

// Shared APNs sender for Live Activity pushes. Underscore prefix → Vercel does not expose this as a
// route; it's imported by the real endpoints.

const b64url = (buf) => Buffer.from(buf).toString('base64url');

let cachedJWT = null; // { jwt, iat } — APNs tokens valid up to 60 min; refresh well before.

function apnsJWT() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.iat < 1500) return cachedJWT.jwt;
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: process.env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: now }));
  const signingInput = `${header}.${claims}`;
  const key = crypto.createPrivateKey(process.env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n'));
  const sig = crypto.sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' });
  const jwt = `${signingInput}.${b64url(sig)}`;
  cachedJWT = { jwt, iat: now };
  return jwt;
}

/**
 * Send one Live Activity push (start via push-to-start, or update) to a device.
 * Returns { status, body }.
 */
export function sendLiveActivityPush({
  pushToken,
  pushToStart = false,
  event,
  contentState,
  attributes,
  attributesType,
  staleSeconds,
  dismissSeconds,
  alert,
}) {
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

  const host = process.env.APNS_ENV === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const body = JSON.stringify({ aps });

  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${host}`);
    client.on('error', reject);
    const stream = client.request({
      ':method': 'POST',
      ':path': `/3/device/${pushToken}`,
      authorization: `bearer ${apnsJWT()}`,
      'apns-topic': `${process.env.APNS_BUNDLE_ID}.push-type.liveactivity`,
      'apns-push-type': 'liveactivity',
      'apns-priority': '10',
    });
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

export function apnsConfigured() {
  return Boolean(process.env.APNS_KEY_ID && process.env.APNS_PRIVATE_KEY);
}
