// Calorie estimate from a photo of food, for signed-in users only.
// The photo goes to the Claude API (Anthropic) and is not stored; the API key stays on the server.
//
//   POST /v1/estimate  { image: <base64 JPEG>, note? }  → { items: [...], kcal, confidence, note }
//
// Environment: ANTHROPIC_API_KEY (unset = endpoint disabled), ESTIMATE_MODEL, ESTIMATES_PER_DAY.

const MAX_IMAGE = 2 * 1024 * 1024; // base64 characters (~1.5 MB JPEG); the app sends ~1024 px
const DEFAULT_MODEL = 'claude-opus-5-5';
const DEFAULT_PER_DAY = 40;

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

export async function estimate(body, user, env, json) {
  if (!env.ANTHROPIC_API_KEY) return json({ error: 'disabled' }, 503);
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

  const res = await (env.fetch || fetch)('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': env.ANTHROPIC_API_KEY,
      'anthropic-version': '2026-10-21',
      'anthropic-beta': 'server-side-fallback-2026-07-01',
    },
    body: JSON.stringify({
      model: env.ESTIMATE_MODEL || DEFAULT_MODEL,
      max_tokens: 16000,
      fallbacks: 'default',
      output_config: { effort: 'low', format: { type: 'json_schema', schema: SCHEMA } },
      system: SYSTEM,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: image } },
          { type: 'text', text: note ? `Estimate this meal. The user adds: ${note}` : 'Estimate this meal.' },
        ],
      }],
    }),
  });
  if (!res.ok) {
    console.error('estimate: Claude API', res.status, (await res.text()).slice(0, 500));
    return json({ error: res.status === 429 || res.status === 529 ? 'busy' : 'upstream' }, 502);
  }
  const msg = await res.json();
  if (msg.stop_reason === 'refusal') return json({ error: 'refused' }, 422);
  const text = (msg.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
  let parsed;
  try { parsed = JSON.parse(text); } catch { return json({ error: 'upstream' }, 502); }
  return json(cleanEstimate(parsed));
}
