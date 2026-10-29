// Unit tests for the photo estimate (no server or network needed): node --test test/estimate.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { estimate, cleanEstimate } from '../src/estimate.js';

const json = (obj, status = 200) => ({ status, obj });
function fakeEnv({ used = 0, reply, status = 200 } = {}) {
  const sent = [];
  const stmt = (sql) => ({ bind: () => ({ first: async () => ({ n: used }), exec: () => sql }) });
  return {
    sent,
    ANTHROPIC_API_KEY: 'sk-test',
    DB: { prepare: stmt, batch: async () => [] },
    fetch: async (url, init) => {
      sent.push({ url, init, body: JSON.parse(init.body) });
      return { ok: status === 200, status, json: async () => reply, text: async () => 'error' };
    },
  };
}
const answer = (obj, extra = {}) => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(obj) }], ...extra });

test('sends the photo with a JSON schema and returns cleaned items', async () => {
  const env = fakeEnv({ reply: answer({ items: [{ name: 'Μουσακάς', grams: 300.4, kcal: 650.6, protein: 30.04, carbs: 40, fat: 38 },
    { name: ' ', grams: 1, kcal: 1, protein: 0, carbs: 0, fat: 0 }], confidence: 'medium', note: 'λάδι: τυπική ποσότητα' }) });
  const r = await estimate({ image: 'AAAA', note: 'μισή μερίδα' }, 'u', env, json);
  assert.equal(r.status, 200);
  assert.deepEqual(r.obj, { items: [{ name: 'Μουσακάς', grams: 300, kcal: 651, protein: 30, carbs: 40, fat: 38 }], kcal: 651,
    confidence: 'medium', note: 'λάδι: τυπική ποσότητα' });
  const { body, init } = env.sent[0];
  assert.equal(init.headers['x-api-key'], 'sk-test');
  assert.equal(body.model, 'claude-haiku-5-5');
  assert.equal(body.fallbacks, undefined); // Haiku has no server-side fallback
  assert.equal(init.headers['anthropic-beta'], undefined);
  assert.equal(body.output_config.format.type, 'json_schema');
  assert.equal(body.messages[0].content[0].source.data, 'AAAA');
  assert.match(body.messages[0].content[1].text, /μισή μερίδα/);
});

test('rejects bad input, the daily limit, refusals and a missing key', async () => {
  assert.equal((await estimate({ image: '<x>' }, 'u', fakeEnv(), json)).status, 400);
  assert.equal((await estimate({}, 'u', fakeEnv(), json)).status, 400);
  assert.equal((await estimate({ image: 'AAAA' }, 'u', fakeEnv({ used: 40 }), json)).status, 429);
  assert.deepEqual((await estimate({ image: 'AAAA' }, 'u', fakeEnv({ reply: { stop_reason: 'refusal', content: [] } }), json)).obj, { error: 'refused' });
  assert.equal((await estimate({ image: 'AAAA' }, 'u', fakeEnv({ status: 529 }), json)).status, 502);
  assert.equal((await estimate({ image: 'AAAA' }, 'u', { ...fakeEnv(), ANTHROPIC_API_KEY: '' }, json)).status, 503);
});

test('cleanEstimate clamps nonsense', () => {
  const c = cleanEstimate({ items: [{ name: 'x', grams: -5, kcal: 1e9, protein: NaN }], confidence: 'sure' });
  assert.deepEqual(c, { items: [{ name: 'x', grams: 0, kcal: 10000, protein: 0, carbs: 0, fat: 0 }], kcal: 10000, confidence: 'low', note: '' });
});

test('larger Claude models get the refusal fallback', async () => {
  const env = { ...fakeEnv({ reply: answer({ items: [], confidence: 'low', note: '' }) }), ESTIMATE_MODEL: 'claude-opus-5-5' };
  await estimate({ image: 'AAAA' }, 'u', env, json);
  assert.equal(env.sent[0].body.fallbacks, 'default');
  assert.equal(env.sent[0].init.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
});

const gemini = (obj, extra = {}) => ({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(obj) }] } }], ...extra });
const geminiEnv = (opts) => ({ ...fakeEnv(opts), ESTIMATE_PROVIDER: 'gemini', ANTHROPIC_API_KEY: '', GEMINI_API_KEY: 'g-test' });

test('gemini: same answer shape, upper-case schema types, no additionalProperties', async () => {
  const env = geminiEnv({ reply: gemini({ items: [{ name: 'Μπανάνα', grams: 120, kcal: 105, protein: 1.3, carbs: 27, fat: 0.4 }], confidence: 'high', note: '' }) });
  const r = await estimate({ image: 'AAAA' }, 'u', env, json);
  assert.deepEqual(r.obj, { items: [{ name: 'Μπανάνα', grams: 120, kcal: 105, protein: 1.3, carbs: 27, fat: 0.4 }], kcal: 105, confidence: 'high', note: '' });
  const { url, init, body } = env.sent[0];
  assert.equal(url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent');
  assert.equal(init.headers['x-goog-api-key'], 'g-test');
  assert.equal(body.contents[0].parts[0].inline_data.data, 'AAAA');
  const schema = body.generationConfig.response_schema;
  assert.equal(schema.type, 'OBJECT');
  assert.equal(schema.properties.items.items.properties.kcal.type, 'NUMBER');
  assert.ok(!JSON.stringify(schema).includes('additionalProperties'));
});

test('gemini: blocked photos, errors and a missing key', async () => {
  assert.equal((await estimate({ image: 'AAAA' }, 'u', geminiEnv({ reply: { promptFeedback: { blockReason: 'SAFETY' } } }), json)).status, 422);
  assert.equal((await estimate({ image: 'AAAA' }, 'u', geminiEnv({ reply: { candidates: [{ finishReason: 'IMAGE_SAFETY' }] } }), json)).status, 422);
  assert.deepEqual((await estimate({ image: 'AAAA' }, 'u', geminiEnv({ status: 429 }), json)).obj, { error: 'busy' });
  assert.equal((await estimate({ image: 'AAAA' }, 'u', { ...geminiEnv(), GEMINI_API_KEY: '' }, json)).status, 503);
});

test('a stuck or unreachable AI service answers busy', async () => {
  const env = { ...fakeEnv(), fetch: async () => { throw Object.assign(new Error('t'), { name: 'TimeoutError' }); } };
  assert.deepEqual((await estimate({ image: 'AAAA' }, 'u', env, json)).obj, { error: 'busy' });
});
