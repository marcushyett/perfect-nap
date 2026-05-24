// Health check — confirms the deploy is live and which env vars are present (never returns secrets).
export default function handler(req, res) {
  res.status(200).json({
    ok: true,
    service: 'perfectnap-push-relay',
    apnsConfigured: Boolean(process.env.APNS_KEY_ID && process.env.APNS_PRIVATE_KEY),
    apnsEnv: process.env.APNS_ENV || 'production',
    hasSecret: Boolean(process.env.RELAY_SHARED_SECRET),
    time: new Date().toISOString(),
  });
}
