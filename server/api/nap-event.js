import { kv, kvConfigured } from './_kv.js';
import { sendLiveActivityPush, apnsConfigured } from './_apns.js';

// POST /api/nap-event
//   { babyKey, deviceID(sender), event?, contentState, attributes?, attributesType?, staleSeconds?, dismissSeconds? }
// Pushes the new Live Activity state to every OTHER registered device for this baby: an update if that
// device has a live activity token, otherwise a push-to-start (so a brand-new lock-screen activity
// appears). The sender's own device is skipped (it updates its activity locally).
//
// Phase 2 hook: this is also where all-users nap events would be persisted for model training — gated
// behind a privacy-policy update, so not done here yet.
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if ((req.headers['x-relay-secret'] || '') !== process.env.RELAY_SHARED_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  if (!apnsConfigured()) return res.status(503).json({ error: 'APNs not configured' });
  if (!kvConfigured()) return res.status(503).json({ error: 'KV not configured' });

  const { babyKey, deviceID, event, contentState, attributes, attributesType, staleSeconds, dismissSeconds } = req.body || {};
  if (!babyKey || !contentState) return res.status(400).json({ error: 'babyKey and contentState are required' });

  const devices = await kv.hgetallParsed(`baby:${babyKey}`);
  const targets = Object.values(devices).filter((d) => d && d.deviceID && d.deviceID !== deviceID);

  const results = [];
  for (const d of targets) {
    try {
      if (d.activityToken) {
        const r = await sendLiveActivityPush({ pushToken: d.activityToken, pushToStart: false, event, contentState, staleSeconds, dismissSeconds });
        results.push({ deviceID: d.deviceID, mode: 'update', status: r.status });
        // Activity token gone/expired → fall back to starting a fresh one.
        if ((r.status === 410 || r.status === 400) && d.pushToStartToken) {
          const r2 = await sendLiveActivityPush({ pushToken: d.pushToStartToken, pushToStart: true, event: 'start', contentState, attributes, attributesType, staleSeconds });
          results.push({ deviceID: d.deviceID, mode: 'start-fallback', status: r2.status });
        }
      } else if (d.pushToStartToken) {
        const r = await sendLiveActivityPush({ pushToken: d.pushToStartToken, pushToStart: true, event: 'start', contentState, attributes, attributesType, staleSeconds });
        results.push({ deviceID: d.deviceID, mode: 'start', status: r.status });
      } else {
        results.push({ deviceID: d.deviceID, mode: 'skip', reason: 'no token' });
      }
    } catch (e) {
      results.push({ deviceID: d.deviceID, error: String(e && e.message ? e.message : e) });
    }
  }

  return res.status(200).json({ targets: targets.length, results });
}
