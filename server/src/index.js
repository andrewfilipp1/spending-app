// Cloudflare Workers entry point (optional alternative to the Node.js server).
import { handle } from './app.js';

export default {
  fetch: (req, env) => handle(req, { ...env, clientIP: (r) => r.headers.get('CF-Connecting-IP') }),
};
