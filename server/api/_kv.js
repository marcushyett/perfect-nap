// Minimal Upstash Redis REST client (zero deps; uses global fetch). Underscore prefix → not a route.
// Works with either the Vercel-KV (KV_REST_API_*) or Upstash (UPSTASH_REDIS_REST_*) env var names.

function creds() {
  const url = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
  return { url, token };
}

export function kvConfigured() {
  const { url, token } = creds();
  return Boolean(url && token);
}

async function cmd(args) {
  const { url, token } = creds();
  if (!url || !token) throw new Error('KV not configured');
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || (j && j.error)) throw new Error((j && j.error) || `KV HTTP ${r.status}`);
  return j.result;
}

export const kv = {
  hset: (key, field, value) => cmd(['HSET', key, field, value]),
  hdel: (key, field) => cmd(['HDEL', key, field]),
  expire: (key, seconds) => cmd(['EXPIRE', key, String(seconds)]),
  // HGETALL returns a flat [field, value, field, value, …]; fold into an object of parsed JSON values.
  async hgetallParsed(key) {
    const flat = (await cmd(['HGETALL', key])) || [];
    const out = {};
    for (let i = 0; i < flat.length; i += 2) {
      try { out[flat[i]] = JSON.parse(flat[i + 1]); } catch { out[flat[i]] = flat[i + 1]; }
    }
    return out;
  },
};
