import { sendLiveActivityPush, apnsConfigured } from './_apns.js';

// POST /api/push (header X-Relay-Secret) — low-level: forward a single Live Activity push to one
// token. Used for manual testing; app traffic goes through /api/nap-event. Body:
//   { pushToken, pushToStart?, event?, contentState, attributes?, attributesType?, staleSeconds?, dismissSeconds?, alert? }
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!apnsConfigured()) return res.status(503).json({ error: 'APNs not configured — set env vars' });
  if ((req.headers['x-relay-secret'] || '') !== process.env.RELAY_SHARED_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  const { pushToken, contentState } = req.body || {};
  if (!pushToken || !contentState) return res.status(400).json({ error: 'pushToken and contentState are required' });
  try {
    const r = await sendLiveActivityPush(req.body);
    return res.status(r.status === 200 ? 200 : 502).json({ apnsStatus: r.status, apnsBody: r.body });
  } catch (e) {
    return res.status(502).json({ error: String(e && e.message ? e.message : e) });
  }
}
