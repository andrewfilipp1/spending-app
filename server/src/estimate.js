// Calorie estimate from a photo of food, for signed-in users only.
// The photo goes to an AI service and is not stored here; the API key stays on the server.
//
//   POST /v1/estimate  { image: <base64 JPEG>, note? }  → { items: [...], kcal, confidence, note }
//
// Environment:
//   ESTIMATE_PROVIDER  claude (default) | gemini
//   ANTHROPIC_API_KEY  for claude — paid, not used for training
//   GEMINI_API_KEY     for gemini — has a free tier, where Google may use the photos to improve its products
//   ESTIMATE_MODEL     default claude-haiku-5-5 / gemini-3.6-flash
//   ESTIMATES_PER_DAY  default 40
// Without the provider's key the endpoint answers 503.

const MAX_IMAGE = 2 * 1024 * 1024; // base64 characters (~1.5 MB JPEG); the app sends ~1024 px
const MODELS = { claude: 'claude-haiku-5-5', gemini: 'gemini-3.6-flash' };
const DEFAULT_PER_DAY = 40;
const TIMEOUT_MS = 60_000; // a stuck AI service answers "busy" instead of leaving the app waiting

const SYSTEM = `You estimate the nutrition of food in a photo for a personal calorie log.
List each distinct food or drink you can see, with its estimated portion in grams and its calories, protein, carbohydrates and fat for that portion. Use typical Greek recipes and restaurant portions when a dish is Greek.
Name items in Greek. If something is hidden or ambiguous (oil, sauce, a drink's sugar), assume the typical amount and mention it in "note".
Set "confidence" to "low" when the portion or the dish is hard to judge from the photo.
If the photo shows no food, return an empty "items" list and say so in "note".`;

const SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          grams: { type: 'number' },
          kcal: { type: 'number' },
          protein: { type: 'number' },
          carbs: { type: 'number' },
          fat: { type: 'number' },
        },
        required: ['name', 'grams', 'kcal', 'protein', 'carbs', 'fat'],
        additionalProperties: false,
      },
    },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    note: { type: 'string' },
  },
  required: ['items', 'confidence', 'note'],
  additionalProperties: false,
};

const clamp = (v, max) => (Number.isFinite(v) ? Math.min(Math.max(v, 0), max) : 0);
const r1 = (v) => Math.round(v * 10) / 10;

// Keeps only sane values from the model's answer.
export function cleanEstimate(raw) {
  const items = (Array.isArray(raw?.items) ? raw.items : []).slice(0, 20)
    .filter((i) => i && typeof i.name === 'string' && i.name.trim())
    .map((i) => ({
      name: i.name.trim().slice(0, 120),
      grams: Math.round(clamp(i.grams, 5000)),
      kcal: Math.round(clamp(i.kcal, 10000)),
      protein: r1(clamp(i.protein, 1000)),
      carbs: r1(clamp(i.carbs, 1000)),
      fat: r1(clamp(i.fat, 1000)),
    }));
  return {
    items,
    kcal: items.reduce((s, i) => s + i.kcal, 0),
    confidence: ['low', 'medium', 'high'].includes(raw?.confidence) ? raw.confidence : 'low',
    note: typeof raw?.note === 'string' ? raw.note.slice(0, 500) : '',
  };
}

const provider = (env) => (env.ESTIMATE_PROVIDER === 'gemini' ? 'gemini' : 'claude');
const keyOf = (env) => (provider(env) === 'gemini' ? env.GEMINI_API_KEY : env.ANTHROPIC_API_KEY);

export async function estimate(body, user, env, json) {
  if (!keyOf(env)) return json({ error: 'disabled' }, 503);
  const image = body?.image;
  if (typeof image !== 'string' || !image || image.length > MAX_IMAGE || !/^[A-Za-z0-9+/=]+$/.test(image)) {
    return json({ error: 'bad_request' }, 400);
  }
  const note = typeof body.note === 'string' ? body.note.slice(0, 200) : '';

  const now = Date.now();
  const dayAgo = now - 86400000;
  const perDay = Number(env.ESTIMATES_PER_DAY) || DEFAULT_PER_DAY;
  const used = await env.DB.prepare('SELECT COUNT(*) AS n FROM estimates WHERE username = ? AND at > ?').bind(user, dayAgo).first();
  if (used.n >= perDay) return json({ error: 'rate_limited' }, 429);
  await env.DB.batch([
    env.DB.prepare('INSERT INTO estimates (username, at) VALUES (?, ?)').bind(user, now),
    env.DB.prepare('DELETE FROM estimates WHERE at < ?').bind(dayAgo),
  ]);

  const prompt = note ? `Estimate this meal. The user adds: ${note}` : 'Estimate this meal.';
  const ask = provider(env) === 'gemini' ? askGemini : askClaude;
  const r = await ask(image, prompt, env);
  if (r.error) return json({ error: r.error }, r.error === 'refused' ? 422 : 502);
  let parsed;
  try { parsed = JSON.parse(r.text); } catch { return json({ error: 'upstream' }, 502); }
  return json(cleanEstimate(parsed));
}

// fetch with a time limit; a timeout or network failure comes back as a 503-like response.
async function call(env, url, init) {
  try {
    return await (env.fetch || fetch)(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch (err) {
    console.error('estimate:', url.split('/')[2], err.name);
    return { ok: false, status: 503, text: async () => err.name };
  }
}

// Returns { text } with the JSON answer, or { error: 'refused' | 'busy' | 'upstream' }.
async function askClaude(image, prompt, env) {
  const model = env.ESTIMATE_MODEL || MODELS.claude;
  // Haiku has no server-side fallback for declined requests; the larger models do.
  const fallback = !model.startsWith('claude-haiku');
  const res = await call(env, 'https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': '2026-10-21',
      ...(fallback ? { 'anthropic-beta': 'server-side-fallback-2026-07-01' } : {}),
    },
    body: JSON.stringify({
      model,
      max_tokens: 16000,
      ...(fallback ? { fallbacks: 'default' } : {}),
      output_config: { effort: 'low', format: { type: 'json_schema', schema: SCHEMA } },
      system: SYSTEM,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: image } },
          { type: 'text', text: prompt },
        ],
      }],
    }),
  });
  if (!res.ok) {
    console.error('estimate: Claude API', res.status, (await res.text()).slice(0, 500));
    return { error: [429, 503, 529].includes(res.status) ? 'busy' : 'upstream' };
  }
  const msg = await res.json();
  if (msg.stop_reason === 'refusal') return { error: 'refused' };
  return { text: (msg.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('') };
}

// Gemini's response schema is an OpenAPI subset: upper-case types, no additionalProperties.
function geminiSchema(s) {
  if (Array.isArray(s)) return s.map(geminiSchema);
  if (!s || typeof s !== 'object') return s;
  const out = {};
  for (const [k, v] of Object.entries(s)) {
    if (k === 'additionalProperties') continue;
    out[k] = k === 'type' ? String(v).toUpperCase() : k === 'properties' ? Object.fromEntries(Object.entries(v).map(([p, x]) => [p, geminiSchema(x)])) : geminiSchema(v);
  }
  return out;
}

async function askGemini(image, prompt, env) {
  const model = env.ESTIMATE_MODEL || MODELS.gemini;
  const res = await call(env, `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': env.GEMINI_API_KEY },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: SYSTEM }] },
      contents: [{ role: 'user', parts: [{ inline_data: { mime_type: 'image/jpeg', data: image } }, { text: prompt }] }],
      generationConfig: { response_mime_type: 'application/json', response_schema: geminiSchema(SCHEMA) },
    }),
  });
  if (!res.ok) {
    console.error('estimate: Gemini API', res.status, (await res.text()).slice(0, 500));
    return { error: res.status === 429 || res.status === 503 ? 'busy' : 'upstream' };
  }
  const msg = await res.json();
  const c = msg.candidates?.[0];
  if (msg.promptFeedback?.blockReason || !c || ['SAFETY', 'PROHIBITED_CONTENT', 'IMAGE_SAFETY', 'BLOCKLIST'].includes(c.finishReason)) {
    return { error: 'refused' };
  }
  return { text: (c.content?.parts || []).map((p) => p.text || '').join('') };
}
