import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';
import { getPool } from '../lib/database';

// GET /api/health — SHALLOW by default: returns 200 without touching the database.
//
// Why: anything that polls this endpoint (uptime monitors, Logic App schedulers, a
// status page on setInterval) would otherwise reset SQL Serverless's auto-pause timer
// on every call and keep the DB billing compute 24/7. Proven cost overrun in
// trg-directory-website (cost-guardrails Guardrail #11, gotcha #40).
//
// The DB check is gated behind ?deep=1 and is for on-demand diagnostics only.
// Point monitors and schedulers at the shallow form.
export async function health(req: HttpRequest, ctx: InvocationContext): Promise<HttpResponseInit> {
  const deep = req.query.get('deep') === '1';
  if (!deep) {
    return { status: 200, jsonBody: { ok: true } };
  }

  if (!process.env.SQL_CONNECTION_STRING) {
    // Three-state: null = not probed / not configured, never a false outage.
    return { status: 200, jsonBody: { ok: true, db: null, reason: 'SQL_CONNECTION_STRING not set' } };
  }

  try {
    await getPool();
    return { status: 200, jsonBody: { ok: true, db: 'ok' } };
  } catch (err) {
    ctx.error('Deep health check failed', err);
    return { status: 503, jsonBody: { ok: false, db: 'error' } };
  }
}

app.http('health', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'health',
  handler: health,
});
