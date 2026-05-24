import { kv, kvConfigured } from './_kv.js';

// POST /api/register  { babyKey, deviceID, pushToStartToken?, activityToken? }
// Records this device's current Live Activity tokens under the shared baby so the relay can push to
// it. Merges (so a later activity-token update doesn't wipe the push-to-start token). Send
// activityToken: null explicitly to clear it when the device's activity ends.
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if ((req.headers['x-relay-secret'] || '') !== process.env.RELAY_SHARED_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  if (!kvConfigured()) return res.status(503).json({ error: 'KV not configured — add a store' });

  const body = req.body || {};
  const { babyKey, deviceID } = body;
  if (!babyKey || !deviceID) return res.status(400).json({ error: 'babyKey and deviceID are required' });

  const key = `baby:${babyKey}`;
  const existing = (await kv.hgetallParsed(key))[deviceID] || {};
  const record = { ...existing, deviceID, updatedAt: Date.now() };
  if ('pushToStartToken' in body) record.pushToStartToken = body.pushToStartToken;
  if ('activityToken' in body) record.activityToken = body.activityToken;

  await kv.hset(key, deviceID, JSON.stringify(record));
  await kv.expire(key, 60 * 60 * 24 * 60); // keep registrations 60 days

  return res.status(200).json({ ok: true });
}
