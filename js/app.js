import { db } from './db.js';
import * as L from './logic.js';
import { deriveKey, encryptJSON, decryptJSON, randomSalt, PBKDF2_ITERATIONS } from './crypto.js';

const APP_VERSION = self.APP_VERSION || 'dev';
const SCHEMA = 1;

const DEFAULT_CATEGORIES = [
  { id: 'groceries', name: 'Σούπερ μάρκετ', emoji: '🛒', color: '#16a34a', budget: null },
  { id: 'food', name: 'Φαγητό έξω', emoji: '🍔', color: '#ea580c', budget: null },
  { id: 'coffee', name: 'Καφές', emoji: '☕', color: '#a16207', budget: null },
  { id: 'transport', name: 'Μετακινήσεις', emoji: '🚗', color: '#2563eb', budget: null },
  { id: 'home', name: 'Σπίτι & λογαριασμοί', emoji: '🏠', color: '#7c3aed', budget: null },
  { id: 'health', name: 'Υγεία', emoji: '💊', color: '#dc2626', budget: null },
  { id: 'fun', name: 'Διασκέδαση', emoji: '🎉', color: '#db2777', budget: null },
  { id: 'shopping', name: 'Ρούχα & αγορές', emoji: '🛍️', color: '#0d9488', budget: null },
  { id: 'subs', name: 'Συνδρομές', emoji: '📱', color: '#4f46e5', budget: null },
  { id: 'other', name: 'Άλλα', emoji: '📦', color: '#64748b', budget: null },
];

// Used only to pre-select a category for a new merchant; the user's own past choices win.
const MERCHANT_HINTS = [
  [/lidl|σκλαβεν|sklavenitis|masoutis|μασούτ|\bab\b|vasilopoulos|βασιλόπουλ|my ?market|kritikos|κρητικός|galaxias|γαλαξίας|bazaar|market|μάρκετ|φούρν|bakery|φρουτ|κρεοπ|λαϊκή/i, 'groceries'],
  [/coffee|καφ|starbucks|everest|gregory|mikel|γρηγόρ/i, 'coffee'],
  [/efood|wolt|\bbox\b|pizza|πίτσα|souvlaki|σουβλ|ψητοπ|restaurant|εστιατ|ταβέρν|burger|mcdonald|goody/i, 'food'],
  [/shell|\bbp\b|\beko\b|avin|aegean|revoil|elin|καύσιμ|fuel|oasa|οασα|taxi|ταξί|uber|freenow|parking|στάθμευ|attiki odos|αττική οδός|metro|μετρό/i, 'transport'],
  [/φαρμακ|pharma|clinic|κλινικ|ιατρ|γιατρ|οδοντ/i, 'health'],
  [/netflix|spotify|apple\.com|icloud|disney|youtube|google|prime|vodafone|cosmote|\bnova\b|wind/i, 'subs'],
  [/δεη|\bdei\b|eydap|εΥΔΑΠ|ενοίκ|ikea|praktiker|leroy/i, 'home'],
  [/zara|h&m|bershka|pull ?& ?bear|jumbo|public|plaisio|πλαίσιο|kotsovolos|κωτσόβολ|skroutz|shein/i, 'shopping'],
  [/cinema|σινεμ|village|odeon|\bbar\b|club|θέατρ|ticket/i, 'fun'],
];

const KINDS = ['day', 'week', 'month', 'year'];
const KIND_LABEL = { day: 'Ημερήσιο', week: 'Εβδομαδιαίο', month: 'Μηνιαίο', year: 'Ετήσιο' };
const PERIOD_NAME = { day: 'Σήμερα', week: 'Αυτή την εβδομάδα', month: 'Αυτόν τον μήνα', year: 'Φέτος' };
const BASIS = { day: 'ημερήσιου budget', week: 'εβδομαδιαίου budget', month: 'μηνιαίου budget', year: 'ετήσιου budget' };
const TITLES = { home: 'Τα Οικονομικά μου', history: 'Ιστορικό', stats: 'Στατιστικά', settings: 'Ρυθμίσεις' };
const DAY_CHOICES = [1, 2, 3, 4, 5, 6, 7, 10, 14, 30, 60, 90, 180, 365];
const AUTOLOCK_CHOICES = [[0, 'Αμέσως'], [60, 'Μετά από 1 λεπτό'], [300, 'Μετά από 5 λεπτά'], [900, 'Μετά από 15 λεπτά']];

const ICON = {
  apple: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.2-1.7-3-1.9-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.4.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9-.1 0-2.9-1.1-2.9-4.2zM13.9 5.3c.7-.8 1.2-2 1-3.2-1 .1-2.2.7-3 1.5-.6.7-1.2 1.9-1 3.1 1.1.1 2.3-.6 3-1.4z"/></svg>',
  lock: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>',
  chevL: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>',
  chevR: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg>',
};

// ---------- state ----------

const state = {
  data: null, // { schema, settings, categories, purchases } — decrypted, in memory only
  key: null, // AES key while unlocked (non-extractable)
  meta: null, // { schema, encrypted, salt?, iterations?, numeric? }
  tab: 'home',
  stats: { kind: 'month', ref: L.today(), mode: 'spread', cat: null, sel: null },
  history: { q: '', cat: '' },
  hiddenAt: null,
};

const S = () => state.data.settings;
const P = () => state.data.purchases;
const C = () => state.data.categories;

// ---------- small utils ----------

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`);
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
const isHex = (c) => /^#[0-9a-f]{6}$/i.test(c);

let moneyFmt;
const money = (cents) => {
  moneyFmt ??= new Intl.NumberFormat('el-GR', { style: 'currency', currency: S().currency || 'EUR' });
  return moneyFmt.format((cents || 0) / 100);
};

const catById = (id) => C().find((c) => c.id === id) || C().find((c) => c.id === 'other');
const purchaseTotal = (p) => p.items.reduce((s, i) => s + i.cents, 0);
const byNewest = (a, b) => (b.date === a.date ? (b.createdAt || 0) - (a.createdAt || 0) : b.date < a.date ? -1 : 1);
const level = (ratio) => (ratio >= 1 ? 'red' : ratio >= 0.8 ? 'amber' : 'green');
const ratioOf = (spent, budget) => (budget > 0 ? spent / budget : spent > 0 ? 1 : 0);

function toast(msg) {
  const el = $('#toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => el.classList.remove('show'), 2600);
}

// The CSP forbids inline style attributes, so dynamic widths/colours go through CSSOM.
function applyStyles(root) {
  root.querySelectorAll('[data-w]').forEach((el) => {
    el.style.width = `${Math.max(0, Math.min(100, Number(el.dataset.w) || 0))}%`;
  });
  root.querySelectorAll('[data-color]').forEach((el) => {
    if (isHex(el.dataset.color)) el.style.setProperty('--c', el.dataset.color);
  });
}

// ---------- data validation & migration ----------

const int = (v, min, max, dflt) => (Number.isInteger(v) && v >= min && v <= max ? v : dflt);
const str = (v, max = 200) => (typeof v === 'string' ? v.slice(0, max) : '');
const isISODate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
const optCents = (v) => (Number.isInteger(v) && v >= 0 && v < 1e11 ? v : null);

function defaultData() {
  return {
    schema: SCHEMA,
    settings: { budgets: { day: null, week: null, month: null, year: null }, weekStart: 1, currency: 'EUR', autoLockSec: 60 },
    categories: structuredClone(DEFAULT_CATEGORIES),
    purchases: [],
  };
}

// Rebuilds the data from known fields only, so a corrupted or crafted backup cannot inject anything.
function sanitize(raw) {
  const def = defaultData();
  if (!raw || typeof raw !== 'object') return def;
  const rs = raw.settings || {};
  const settings = {
    budgets: Object.fromEntries(KINDS.map((k) => [k, optCents(rs.budgets?.[k])])),
    weekStart: rs.weekStart === 0 ? 0 : 1,
    currency: /^[A-Z]{3}$/.test(rs.currency) ? rs.currency : 'EUR',
    autoLockSec: AUTOLOCK_CHOICES.some(([s]) => s === rs.autoLockSec) ? rs.autoLockSec : 60,
  };
  let categories = Array.isArray(raw.categories)
    ? raw.categories
      .filter((c) => c && typeof c.id === 'string' && c.id)
      .map((c) => ({
        id: str(c.id, 64),
        name: str(c.name, 60) || 'Κατηγορία',
        emoji: str(c.emoji, 16) || '•',
        color: isHex(c.color) ? c.color : '#64748b',
        budget: optCents(c.budget),
      }))
    : def.categories;
  if (!categories.length) categories = def.categories;
  if (!categories.some((c) => c.id === 'other')) categories.push(def.categories.find((c) => c.id === 'other'));
  const catIds = new Set(categories.map((c) => c.id));
  const purchases = (Array.isArray(raw.purchases) ? raw.purchases : [])
    .filter((p) => p && isISODate(p.date) && Array.isArray(p.items))
    .map((p) => ({
      id: str(p.id, 64) || uid(),
      date: p.date,
      store: str(p.store, 120),
      note: str(p.note, 1000),
      source: p.source === 'applepay' ? 'applepay' : 'manual',
      createdAt: Number.isFinite(p.createdAt) ? p.createdAt : 0,
      updatedAt: Number.isFinite(p.updatedAt) ? p.updatedAt : 0,
      items: p.items
        .filter((i) => i && Number.isInteger(i.cents) && i.cents > 0 && i.cents < 1e11)
        .map((i) => ({
          id: str(i.id, 64) || uid(),
          name: str(i.name, 120) || 'Αγορά',
          cents: i.cents,
          cat: catIds.has(i.cat) ? i.cat : 'other',
          days: int(i.days, 1, 3660, 1),
        })),
    }))
    .filter((p) => p.items.length);
  return { schema: SCHEMA, settings, categories, purchases };
}

// ---------- persistence ----------

let saveChain = Promise.resolve();

function save() {
  const snapshot = structuredClone(state.data);
  const key = state.key;
  saveChain = saveChain
    .then(async () => db.set('data', key ? await encryptJSON(key, snapshot) : snapshot))
    .catch((err) => {
      console.error(err);
      toast('Σφάλμα αποθήκευσης');
    });
  return saveChain;
}

async function writeDataAndMeta(data, meta) {
  await saveChain;
  await db.setMany({ data, meta });
}

async function requestPersist() {
  try {
    if (navigator.storage?.persist && !(await navigator.storage.persisted())) await navigator.storage.persist();
  } catch { /* not supported */ }
}

// ---------- boot / lock ----------

async function boot() {
  bindChrome();
  registerServiceWorker();
  state.meta = (await db.get('meta')) || null;
  if (state.meta?.encrypted) {
    showLock();
    return;
  }
  const raw = await db.get('data');
  state.data = sanitize(raw);
  if (!state.meta) {
    state.meta = { schema: SCHEMA, encrypted: false };
    await db.set('meta', state.meta);
  }
  if (!raw || raw.schema !== SCHEMA) await save();
  start();
}

function start() {
  $('#lock').hidden = true;
  $('#app').hidden = false;
  moneyFmt = null;
  render();
  handleUrlParams();
  requestPersist();
}

function lockNow() {
  if (!state.meta?.encrypted || !state.data) return;
  state.key = null;
  state.data = null;
  closeSheet();
  $('#view').innerHTML = '';
  showLock();
}

const FAIL_KEY = 'unlockFails';
function readFails() {
  try { return JSON.parse(localStorage.getItem(FAIL_KEY)) || { n: 0, at: 0 }; } catch { return { n: 0, at: 0 }; }
}
function writeFails(v) {
  try { localStorage.setItem(FAIL_KEY, JSON.stringify(v)); } catch { /* storage blocked */ }
}
// After 5 wrong attempts: 30s, 60s, 120s… up to 15 minutes between tries.
function lockoutRemaining() {
  const { n, at } = readFails();
  if (n < 5) return 0;
  const wait = Math.min(15 * 60, 30 * 2 ** (n - 5)) * 1000;
  return Math.max(0, at + wait - Date.now());
}

function showLock() {
  $('#app').hidden = true;
  const lock = $('#lock');
  lock.hidden = false;
  const input = $('#lockInput');
  input.value = '';
  input.inputMode = state.meta.numeric ? 'numeric' : 'text';
  $('#lockError').textContent = '';
  setTimeout(() => input.focus(), 50);
}

async function tryUnlock(pass) {
  const err = $('#lockError');
  const wait = lockoutRemaining();
  if (wait > 0) {
    err.textContent = `Πολλές λάθος προσπάθειες. Δοκίμασε ξανά σε ${Math.ceil(wait / 1000)} δευτ.`;
    return;
  }
  const btn = $('#lockSubmit');
  btn.disabled = true;
  btn.textContent = 'Ξεκλείδωμα…';
  err.textContent = '';
  try {
    const key = await deriveKey(pass, state.meta.salt, state.meta.iterations);
    const data = await decryptJSON(key, await db.get('data'));
    state.key = key;
    state.data = sanitize(data);
    writeFails({ n: 0, at: 0 });
    start();
  } catch {
    const f = readFails();
    writeFails({ n: f.n + 1, at: Date.now() });
    err.textContent = 'Λάθος κωδικός';
    $('#lockInput').select();
  } finally {
    btn.disabled = false;
    btn.textContent = 'Ξεκλείδωμα';
  }
}

async function forgotPasscode() {
  if (!confirm('Ο κωδικός δεν μπορεί να ανακτηθεί — ούτε από εμάς. Χωρίς αυτόν τα κρυπτογραφημένα δεδομένα δεν διαβάζονται.\n\nΘέλεις να διαγράψεις τα πάντα και να ξεκινήσεις από την αρχή; (Μετά μπορείς να κάνεις επαναφορά από αντίγραφο ασφαλείας.)')) return;
  if (!confirm('Σίγουρα; Όλα τα δεδομένα αυτής της συσκευής θα διαγραφούν οριστικά.')) return;
  await db.clear();
  writeFails({ n: 0, at: 0 });
  location.reload();
}

// ---------- chrome (nav, lock screen, visibility) ----------

function bindChrome() {
  document.querySelectorAll('.tabbar [data-tab]').forEach((b) => b.addEventListener('click', () => go(b.dataset.tab)));
  $('#addBtn').addEventListener('click', () => openEditor());
  $('#lockTopBtn').addEventListener('click', lockNow);
  $('#lockForm').addEventListener('submit', (e) => {
    e.preventDefault();
    tryUnlock($('#lockInput').value);
  });
  $('#lockForgot').addEventListener('click', forgotPasscode);

  const view = $('#view');
  view.addEventListener('click', (e) => {
    const el = e.target.closest('[data-action]');
    if (el && view.contains(el)) actions[el.dataset.action]?.(el, e);
  });
  view.addEventListener('change', (e) => {
    const el = e.target.closest('[data-change]');
    if (el) changes[el.dataset.change]?.(el, e);
  });
  view.addEventListener('input', (e) => {
    const el = e.target.closest('[data-input]');
    if (el) inputs[el.dataset.input]?.(el, e);
  });

  document.addEventListener('visibilitychange', () => {
    if (!state.meta?.encrypted || !state.data) return;
    if (document.hidden) {
      state.hiddenAt = Date.now();
      if (S().autoLockSec === 0) lockNow();
    } else if (state.hiddenAt && Date.now() - state.hiddenAt >= S().autoLockSec * 1000) {
      lockNow();
    }
  });
}

function go(tab) {
  state.tab = tab;
  render();
  window.scrollTo({ top: 0 });
}

function render() {
  if (!state.data) return;
  const views = { home: renderHome, history: renderHistory, stats: renderStats, settings: renderSettings };
  const view = $('#view');
  view.innerHTML = views[state.tab]();
  applyStyles(view);
  document.querySelectorAll('.tabbar [data-tab]').forEach((b) => b.classList.toggle('active', b.dataset.tab === state.tab));
  $('#title').textContent = TITLES[state.tab];
  $('#lockTopBtn').hidden = !state.meta?.encrypted;
  if (state.tab === 'settings') fillStorageStatus();
}

// ---------- home ----------

function renderHome() {
  const s = S();
  const hasBudget = KINDS.some((k) => s.budgets[k] != null);
  if (!P().length && !hasBudget) return welcome();

  const t = L.today();
  const allocs = L.allocations(P(), 'spread');
  const spentIn = (kind) => {
    const { start, end } = L.period(kind, t, s.weekStart);
    return L.sum(allocs.filter((a) => L.inRange(a, start, end)));
  };

  const rows = KINDS.filter((k) => k !== 'day' && (k !== 'year' || s.budgets.year != null)).map((k) => {
    const b = s.budgets[k];
    const spent = spentIn(k);
    const r = ratioOf(spent, b);
    return `<div class="prow">
      <div class="prow-head"><span>${PERIOD_NAME[k]}</span>
        <span><strong>${money(spent)}</strong>${b != null ? ` <span class="muted">/ ${money(b)}</span>` : ''}</span></div>
      ${b != null ? `<div class="bar"><div class="bar-fill ${level(r)}" data-w="${r * 100}"></div></div>
        <div class="prow-foot muted">${spent <= b ? `απομένουν ${money(b - spent)}` : `υπέρβαση ${money(spent - b)}`}</div>` : ''}
    </div>`;
  }).join('');

  const { start: mStart, end: mEnd } = L.period('month', t, s.weekStart);
  const byCat = groupByCat(allocs.filter((a) => L.inRange(a, mStart, mEnd)));
  const maxCat = Math.max(1, ...byCat.map((c) => c.cents));
  const committed = L.sum(allocs.filter((a) => a.date > t));
  const recent = [...P()].sort(byNewest).slice(0, 5);

  return `
    ${installHint()}
    ${homeHero(allocs)}
    <section class="card">${rows}</section>
    ${committed > 0 ? `<p class="note">📅 ${money(committed)} έχουν ήδη κατανεμηθεί σε επόμενες ημέρες.</p>` : ''}
    ${byCat.length ? `<section class="card">
      <div class="card-head"><h2 class="card-title">Κατηγορίες αυτόν τον μήνα</h2>
        <button class="link" data-action="goto" data-tab="stats">Όλα →</button></div>
      ${byCat.slice(0, 6).map((c) => catBar(c, maxCat)).join('')}
    </section>` : ''}
    <section class="card">
      <div class="card-head"><h2 class="card-title">Πρόσφατες αγορές</h2>
        ${P().length ? '<button class="link" data-action="goto" data-tab="history">Όλες →</button>' : ''}</div>
      ${recent.length ? `<div class="plist">${recent.map(purchaseCard).join('')}</div>`
        : '<p class="muted">Δεν υπάρχουν ακόμη αγορές. Πάτα <strong>+</strong> για να προσθέσεις.</p>'}
    </section>`;
}

function homeHero(allocs) {
  const s = S();
  const t = L.today();
  const spentToday = L.sum(allocs.filter((a) => a.date === t));
  const opts = [];
  if (s.budgets.day != null) opts.push({ cents: s.budgets.day, kind: 'day' });
  for (const k of ['week', 'month', 'year']) {
    if (s.budgets[k] != null) opts.push({ cents: L.dailyAllowance(s.budgets[k], allocs, k, t, s.weekStart), kind: k });
  }
  if (!opts.length) {
    return `<section class="hero">
      <div class="hero-label">Ξόδεψες σήμερα</div>
      <div class="hero-amount">${money(spentToday)}</div>
      <button class="hero-link" data-action="goto" data-tab="settings">Όρισε budget για να βλέπεις τι σου απομένει →</button>
    </section>`;
  }
  // The most restrictive budget decides what is safe to spend today.
  const best = opts.reduce((m, o) => (o.cents < m.cents ? o : m));
  const allowance = Math.max(0, best.cents);
  const left = allowance - spentToday;
  const r = ratioOf(spentToday, allowance);
  return `<section class="hero ${left < 0 ? 'over' : ''}">
    <div class="hero-label">${left >= 0 ? 'Διαθέσιμα σήμερα' : 'Υπέρβαση σήμερα'}</div>
    <div class="hero-amount">${money(Math.abs(left))}</div>
    <div class="bar light"><div class="bar-fill" data-w="${r * 100}"></div></div>
    <div class="hero-sub">${best.cents <= 0
      ? `Το ${KIND_LABEL[best.kind].toLowerCase()} budget έχει ήδη εξαντληθεί`
      : `Ξόδεψες ${money(spentToday)} από ${money(allowance)} · βάσει ${BASIS[best.kind]}`}</div>
  </section>`;
}

function welcome() {
  return `${installHint()}
  <section class="card welcome">
    <div class="welcome-emoji">👋</div>
    <h2>Καλώς ήρθες!</h2>
    <p>Κατέγραψε τις αγορές σου προϊόν-προϊόν, όρισε budget ανά ημέρα, εβδομάδα ή μήνα και δες πού πάνε τα χρήματά σου.</p>
    <p class="muted small">🔒 Τα δεδομένα σου αποθηκεύονται μόνο σε αυτή τη συσκευή. Δεν στέλνονται πουθενά.</p>
    <div class="btn-col">
      <button class="btn primary" data-action="add">Πρόσθεσε την πρώτη αγορά</button>
      <button class="btn" data-action="goto" data-tab="settings">Όρισε budget</button>
    </div>
  </section>`;
}

function installHint() {
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
  if (!ios || navigator.standalone) return '';
  return `<section class="card hint">
    <strong>Εγκατάσταση στο iPhone</strong>
    <p class="small">Πάτα <strong>Κοινοποίηση</strong> ⎋ και μετά <strong>«Προσθήκη στην οθόνη Αφετηρίας»</strong>.
    Έτσι ανοίγει σαν εφαρμογή και το iOS δεν σβήνει τα δεδομένα αν δεν την ανοίξεις για καιρό.</p>
  </section>`;
}

function groupByCat(allocs) {
  const m = new Map();
  for (const a of allocs) m.set(a.cat, (m.get(a.cat) || 0) + a.cents);
  return [...m].map(([cat, cents]) => ({ cat, cents })).sort((a, b) => b.cents - a.cents);
}

function catBar({ cat, cents }, max, opts = {}) {
  const c = catById(cat);
  const pct = opts.total ? Math.round((cents / opts.total) * 100) : null;
  const tag = opts.action ? 'button' : 'div';
  const budget = opts.showBudget && c.budget != null ? ` <span class="muted">/ ${money(c.budget)}</span>` : '';
  return `<${tag} class="catbar ${opts.selected ? 'selected' : ''}" data-color="${c.color}" ${opts.action ? `data-action="${opts.action}" data-cat="${esc(c.id)}"` : ''}>
    <div class="catbar-head"><span>${esc(c.emoji)} ${esc(c.name)}</span>
      <span><strong>${money(cents)}</strong>${budget}${pct != null ? ` <span class="muted">${pct}%</span>` : ''}</span></div>
    <div class="bar"><div class="bar-fill cat" data-w="${(cents / max) * 100}"></div></div>
  </${tag}>`;
}

function purchaseCard(p) {
  const total = purchaseTotal(p);
  const first = catById(p.items[0]?.cat);
  const maxDays = Math.max(...p.items.map((i) => i.days));
  const title = p.store || p.items[0]?.name || 'Αγορά';
  const names = p.items.map((i) => i.name).join(', ');
  return `<button class="pcard" data-action="open-purchase" data-id="${esc(p.id)}">
    <span class="pcard-icon" data-color="${first.color}">${esc(first.emoji)}</span>
    <span class="pcard-main">
      <span class="pcard-title">${esc(title)}</span>
      <span class="pcard-sub">${p.items.length > 1 ? `${p.items.length} προϊόντα · ` : ''}${esc(names)}</span>
    </span>
    <span class="pcard-amt">${money(total)}
      <span class="pcard-meta">${L.dayLabel(p.date)}${maxDays > 1 ? ` · ÷${maxDays} ημ.` : ''}</span></span>
  </button>`;
}

// ---------- history ----------

function renderHistory() {
  const { q, cat } = state.history;
  return `
    <div class="filters">
      <input type="search" class="search" placeholder="Αναζήτηση προϊόντος ή καταστήματος" value="${esc(q)}" data-input="hist-q" aria-label="Αναζήτηση">
      <select data-change="hist-cat" aria-label="Κατηγορία">
        <option value="">Όλες οι κατηγορίες</option>
        ${C().map((c) => `<option value="${esc(c.id)}" ${c.id === cat ? 'selected' : ''}>${esc(c.emoji)} ${esc(c.name)}</option>`).join('')}
      </select>
    </div>
    <div id="historyList">${historyList()}</div>`;
}

function historyList() {
  const { q, cat } = state.history;
  const qq = norm(q);
  const list = [...P()].sort(byNewest).filter((p) => (!cat || p.items.some((i) => i.cat === cat))
    && (!qq || norm(p.store).includes(qq) || norm(p.note).includes(qq) || p.items.some((i) => norm(i.name).includes(qq))));
  if (!list.length) return `<p class="empty">${P().length ? 'Δεν βρέθηκαν αγορές.' : 'Δεν υπάρχουν ακόμη αγορές.'}</p>`;
  const groups = new Map();
  for (const p of list) {
    if (!groups.has(p.date)) groups.set(p.date, []);
    groups.get(p.date).push(p);
  }
  return [...groups].map(([date, ps]) => {
    const dayTotal = ps.reduce((s, p) => s + (cat ? p.items.filter((i) => i.cat === cat).reduce((x, i) => x + i.cents, 0) : purchaseTotal(p)), 0);
    return `<div class="day-group">
      <div class="day-head"><span>${L.dayLabel(date)}</span><span>${money(dayTotal)}</span></div>
      <div class="plist">${ps.map(purchaseCard).join('')}</div>
    </div>`;
  }).join('');
}

// ---------- stats ----------

function renderStats() {
  const st = state.stats;
  const s = S();
  const t = L.today();
  const { start, end } = L.period(st.kind, st.ref, s.weekStart);
  const allocs = L.allocations(P(), st.mode);
  const match = (a) => !st.cat || a.cat === st.cat;
  const inPeriod = allocs.filter((a) => L.inRange(a, start, end));
  const filtered = inPeriod.filter(match);
  const total = L.sum(filtered);

  const prev = L.period(st.kind, L.shiftPeriod(st.kind, st.ref, -1), s.weekStart);
  const prevTotal = L.sum(allocs.filter((a) => L.inRange(a, prev.start, prev.end) && match(a)));
  const delta = prevTotal > 0 ? Math.round(((total - prevTotal) / prevTotal) * 100) : null;

  const elapsedEnd = L.minDate(end, t);
  const elapsed = start > t ? 0 : L.daysBetween(start, elapsedEnd) + 1;
  const avg = elapsed ? L.sum(filtered.filter((a) => a.date <= elapsedEnd)) / elapsed : null;

  const cat = st.cat ? catById(st.cat) : null;
  const budget = cat ? (st.kind === 'month' ? cat.budget : null) : s.budgets[st.kind];

  // Buckets: days for week/month, months for a year.
  let buckets;
  if (st.kind === 'year') {
    const y = Number(start.slice(0, 4));
    buckets = L.MONTHS_SHORT.map((m, i) => {
      const p = L.period('month', L.iso(new Date(y, i, 1, 12)));
      return { ...p, label: m.slice(0, 1), full: `${L.MONTHS[i]} ${y}`, cents: 0, isNow: t >= p.start && t <= p.end };
    });
    for (const a of filtered) buckets[Number(a.date.slice(5, 7)) - 1].cents += a.cents;
  } else {
    const n = L.daysBetween(start, end) + 1;
    const index = new Map();
    buckets = Array.from({ length: n }, (_, i) => {
      const d = L.addDays(start, i);
      const day = L.parse(d);
      index.set(d, i);
      const label = st.kind === 'week' ? L.WEEKDAYS[day.getDay()].slice(0, 2)
        : (i === 0 || (i + 1) % 5 === 0) ? String(day.getDate()) : '';
      return { start: d, end: d, label, full: L.shortDate(d, true), cents: 0, isNow: d === t };
    });
    for (const a of filtered) buckets[index.get(a.date)].cents += a.cents;
  }

  // Dashed reference line: what one bar (a day, or a month in the year view) may cost.
  const m = L.period('month', start);
  const monthDays = L.daysBetween(m.start, m.end) + 1;
  let refLine = null;
  if (st.kind === 'year') {
    refLine = cat ? cat.budget : s.budgets.month ?? (s.budgets.year != null ? s.budgets.year / 12 : null);
  } else if (cat) {
    refLine = cat.budget != null ? cat.budget / monthDays : null;
  } else if (s.budgets.day != null) refLine = s.budgets.day;
  else if (s.budgets.week != null) refLine = s.budgets.week / 7;
  else if (s.budgets.month != null) refLine = s.budgets.month / monthDays;

  const sel = st.sel != null ? buckets[st.sel] : null;
  const byCat = groupByCat(inPeriod);
  const catTotal = L.sum(inPeriod);
  const maxCat = Math.max(1, ...byCat.map((c) => c.cents));
  const top = topItems(filtered);

  return `
    <div class="seg" role="tablist">
      ${[['week', 'Εβδομάδα'], ['month', 'Μήνας'], ['year', 'Έτος']].map(([k, l]) => `<button class="${st.kind === k ? 'on' : ''}" data-action="stats-kind" data-kind="${k}">${l}</button>`).join('')}
    </div>
    <div class="period-nav">
      <button class="icon-btn" data-action="stats-shift" data-dir="-1" aria-label="Προηγούμενη περίοδος">${ICON.chevL}</button>
      <div class="period-label">${L.periodLabel(st.kind, start, end)}</div>
      <button class="icon-btn" data-action="stats-shift" data-dir="1" aria-label="Επόμενη περίοδος">${ICON.chevR}</button>
    </div>
    <div class="seg small">
      <button class="${st.mode === 'spread' ? 'on' : ''}" data-action="stats-mode" data-mode="spread">Κατανάλωση</button>
      <button class="${st.mode === 'paid' ? 'on' : ''}" data-action="stats-mode" data-mode="paid">Πληρωμές</button>
    </div>
    <p class="muted small center">${st.mode === 'spread'
      ? 'Τα προϊόντα που μοίρασες σε πολλές ημέρες μετράνε σε κάθε ημέρα αναλογικά.'
      : 'Κάθε αγορά μετράει ολόκληρη την ημέρα που πληρώθηκε.'}</p>

    ${cat ? `<div class="chip-row"><span class="chip" data-color="${cat.color}">${esc(cat.emoji)} ${esc(cat.name)}</span>
      <button class="link" data-action="stats-cat" data-cat="${esc(cat.id)}">Όλες οι κατηγορίες ✕</button></div>` : ''}

    <div class="tiles">
      <div class="tile"><div class="tile-label">Σύνολο</div><div class="tile-value">${money(total)}</div>
        ${delta != null ? `<div class="tile-sub ${delta > 0 ? 'up' : 'down'}">${delta > 0 ? '▲' : '▼'} ${Math.abs(delta)}% από την προηγ.</div>` : '<div class="tile-sub muted">—</div>'}</div>
      <div class="tile"><div class="tile-label">Μ.Ο. ανά ημέρα</div><div class="tile-value">${avg != null ? money(Math.round(avg)) : '—'}</div>
        <div class="tile-sub muted">${elapsed ? `${elapsed} ημέρες` : 'μελλοντική περίοδος'}</div></div>
      ${budget != null ? `<div class="tile wide"><div class="tile-label">Budget ${esc(cat ? cat.name : KIND_LABEL[st.kind].toLowerCase())}</div>
        <div class="tile-value">${money(total)} <span class="muted">/ ${money(budget)}</span></div>
        <div class="bar"><div class="bar-fill ${level(ratioOf(total, budget))}" data-w="${ratioOf(total, budget) * 100}"></div></div>
        <div class="tile-sub muted">${total <= budget ? `απομένουν ${money(budget - total)}` : `υπέρβαση ${money(total - budget)}`}</div></div>` : ''}
    </div>

    <section class="card">
      <div class="chart-caption">${sel ? `<strong>${esc(sel.full)}</strong> · ${money(sel.cents)}` : '<span class="muted">Πάτα μια μπάρα για λεπτομέρειες</span>'}</div>
      ${barChart(buckets, { refLine, color: cat?.color })}
    </section>

    <section class="card">
      <h2 class="card-title">Ανά κατηγορία</h2>
      ${byCat.length ? byCat.map((c) => catBar(c, maxCat, { total: catTotal, action: 'stats-cat', selected: c.cat === st.cat, showBudget: st.kind === 'month' })).join('')
        : '<p class="muted">Καμία δαπάνη σε αυτή την περίοδο.</p>'}
    </section>

    ${top.length ? `<section class="card">
      <h2 class="card-title">Κορυφαία προϊόντα${cat ? ` · ${esc(cat.name)}` : ''}</h2>
      <ol class="top-list">${top.map((x) => `<li><span>${esc(x.name)} <span class="muted">×${x.count}</span></span><strong>${money(x.cents)}</strong></li>`).join('')}</ol>
    </section>` : ''}`;
}

function topItems(allocs) {
  const m = new Map();
  for (const a of allocs) {
    const k = norm(a.name);
    const e = m.get(k) || { name: a.name, cents: 0, pids: new Set() };
    e.cents += a.cents;
    e.pids.add(a.pid);
    m.set(k, e);
  }
  return [...m.values()].map((e) => ({ name: e.name, cents: e.cents, count: e.pids.size }))
    .sort((a, b) => b.cents - a.cents).slice(0, 8);
}

function barChart(buckets, { refLine, color }) {
  const W = 360;
  const H = 170;
  const top = 12;
  const bottom = 20;
  const n = buckets.length;
  const max = Math.max(1, ...buckets.map((b) => b.cents), refLine || 0) * 1.08;
  const bw = W / n;
  const y = (c) => H - bottom - ((H - bottom - top) * c) / max;
  const bars = buckets.map((b, i) => {
    const h = b.cents ? Math.max(2, H - bottom - y(b.cents)) : 0;
    const x = i * bw + bw * 0.16;
    const w = bw * 0.68;
    const cls = ['bar-rect', b.isNow ? 'now' : '', state.stats.sel === i ? 'sel' : ''].join(' ');
    return `<g data-action="stats-bar" data-i="${i}" class="bar-hit">
      <rect x="${i * bw}" y="0" width="${bw}" height="${H}" fill="transparent"/>
      ${h ? `<rect class="${cls}" x="${x}" y="${H - bottom - h}" width="${w}" height="${h}" rx="${Math.min(3, w / 3)}" ${color && isHex(color) ? `fill="${color}"` : ''}/>` : ''}
      ${b.label ? `<text x="${i * bw + bw / 2}" y="${H - 5}" text-anchor="middle" class="axis ${b.isNow ? 'now' : ''}">${esc(b.label)}</text>` : ''}
    </g>`;
  }).join('');
  const ref = refLine ? `<line x1="0" x2="${W}" y1="${y(refLine)}" y2="${y(refLine)}" class="ref-line"/>
    <text x="${W - 2}" y="${y(refLine) - 3}" text-anchor="end" class="axis ref">budget</text>` : '';
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Γράφημα δαπανών">
    <line x1="0" x2="${W}" y1="${H - bottom}" y2="${H - bottom}" class="baseline"/>${bars}${ref}</svg>`;
}

// ---------- settings ----------

function renderSettings() {
  const s = S();
  const encrypted = state.meta?.encrypted;
  const appUrl = `${location.origin}${location.pathname}`;
  return `
  <section class="card">
    <h2 class="card-title">Budget</h2>
    <p class="muted small">Άφησε κενό ό,τι δεν χρειάζεσαι. Το «Διαθέσιμα σήμερα» βγαίνει από το πιο αυστηρό budget.</p>
    ${KINDS.map((k) => `<label class="setting-row"><span>${KIND_LABEL[k]}</span>
      <span class="money-input"><input inputmode="decimal" data-change="budget" data-kind="${k}" value="${L.centsToInput(s.budgets[k])}" placeholder="—" autocomplete="off"><span>€</span></span></label>`).join('')}
    <label class="setting-row"><span>Η εβδομάδα ξεκινά</span>
      <select data-change="weekstart"><option value="1" ${s.weekStart === 1 ? 'selected' : ''}>Δευτέρα</option><option value="0" ${s.weekStart === 0 ? 'selected' : ''}>Κυριακή</option></select></label>
  </section>

  <section class="card">
    <div class="card-head"><h2 class="card-title">Κατηγορίες</h2><button class="link" data-action="new-cat">+ Νέα</button></div>
    <div class="cat-list">
      ${C().map((c) => `<button class="cat-row" data-action="edit-cat" data-id="${esc(c.id)}">
        <span class="pcard-icon" data-color="${c.color}">${esc(c.emoji)}</span><span class="grow">${esc(c.name)}</span>
        <span class="muted small">${c.budget != null ? `${money(c.budget)}/μήνα` : ''}</span><span class="chev">›</span></button>`).join('')}
    </div>
  </section>

  <section class="card">
    <h2 class="card-title">${ICON.apple} Apple Pay</h2>
    <p class="small">Η Apple δεν επιτρέπει σε εφαρμογές web να διαβάζουν απευθείας το Wallet. Με έναν αυτοματισμό στις <strong>Συντομεύσεις</strong> όμως, κάθε πληρωμή αντιγράφεται και την περνάς με ένα πάτημα:</p>
    <ol class="steps small">
      <li>Άνοιξε <strong>Συντομεύσεις → Αυτοματισμός → +</strong> και διάλεξε <strong>«Συναλλαγή»</strong> (Transaction).</li>
      <li>Επίλεξε τις κάρτες σου και <strong>«Εκτέλεση αμέσως»</strong>.</li>
      <li>Πρόσθεσε ενέργεια <strong>«Κείμενο»</strong> με περιεχόμενο: <code>Ποσό;Έμπορος</code> — βάλε τις μεταβλητές <em>Ποσό</em> και <em>Έμπορος</em> από την «Είσοδο συντόμευσης».</li>
      <li>Πρόσθεσε ενέργεια <strong>«Αντιγραφή στο πρόχειρο»</strong> και (προαιρετικά) <strong>«Εμφάνιση ειδοποίησης»</strong>.</li>
      <li>Μετά την πληρωμή: άνοιξε την εφαρμογή → <strong>+</strong> → <strong>«Επικόλληση από Apple Pay»</strong>, και χώρισε το ποσό σε προϊόντα αν θες.</li>
    </ol>
    <details class="small"><summary>Εναλλακτικά: άνοιγμα με σύνδεσμο (Safari / υπολογιστής)</summary>
      <p>Αντί για «Αντιγραφή», χρησιμοποίησε <strong>«Άνοιγμα URL»</strong>:</p>
      <code class="block">${esc(appUrl)}?amount=[Ποσό]&amp;merchant=[Έμπορος]</code>
      <p class="muted">Στο iPhone ο σύνδεσμος ανοίγει στο Safari, που έχει ξεχωριστό χώρο αποθήκευσης από την εγκατεστημένη εφαρμογή — γι’ αυτό προτείνεται το πρόχειρο.</p>
    </details>
    <button class="btn full" data-action="test-paste">Δοκιμή: διάβασε το πρόχειρο</button>
  </section>

  <section class="card">
    <h2 class="card-title">${ICON.lock} Ασφάλεια & ιδιωτικότητα</h2>
    <ul class="facts small">
      <li>✅ Όλα τα δεδομένα μένουν <strong>μόνο σε αυτή τη συσκευή</strong> — χωρίς server, λογαριασμό, analytics ή tracking.</li>
      <li>✅ Καμία εξωτερική βιβλιοθήκη· αυστηρή πολιτική ασφαλείας (CSP) που μπλοκάρει κάθε σύνδεση προς τρίτους.</li>
      <li>${encrypted ? '✅' : '⚠️'} Κρυπτογράφηση AES-256-GCM με κωδικό: <strong>${encrypted ? 'ενεργή' : 'ανενεργή'}</strong></li>
      <li>Μόνιμη αποθήκευση: <span id="persistStatus">…</span></li>
    </ul>
    ${encrypted ? `
      <label class="setting-row"><span>Αυτόματο κλείδωμα</span>
        <select data-change="autolock">${AUTOLOCK_CHOICES.map(([v, l]) => `<option value="${v}" ${s.autoLockSec === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
      <div class="btn-col">
        <button class="btn" data-action="change-pass">Αλλαγή κωδικού</button>
        <button class="btn" data-action="lock-now">Κλείδωμα τώρα</button>
        <button class="btn danger-text" data-action="disable-enc">Απενεργοποίηση κρυπτογράφησης</button>
      </div>`
    : `<p class="small">Με κωδικό, τα δεδομένα κρυπτογραφούνται στη συσκευή και η εφαρμογή κλειδώνει όταν την αφήνεις. <strong>Αν ξεχάσεις τον κωδικό, τα δεδομένα δεν ανακτώνται.</strong></p>
      <button class="btn primary full" data-action="enable-enc">Ενεργοποίηση κωδικού & κρυπτογράφησης</button>`}
  </section>

  <section class="card">
    <h2 class="card-title">Αντίγραφα ασφαλείας</h2>
    <p class="small muted">Τα δεδομένα υπάρχουν μόνο εδώ. Κράτα αντίγραφο (π.χ. στα Αρχεία/iCloud Drive) για να μη χαθούν αν αλλάξεις κινητό.
      ${encrypted ? 'Το αντίγραφο είναι κρυπτογραφημένο με τον κωδικό σου.' : 'Χωρίς κωδικό, το αντίγραφο είναι αναγνώσιμο από όποιον το έχει.'}</p>
    <div class="btn-col">
      <button class="btn" data-action="export">Εξαγωγή αντιγράφου</button>
      <label class="btn">Επαναφορά από αντίγραφο<input type="file" accept="application/json,.json" data-change="import" hidden></label>
    </div>
  </section>

  <section class="card">
    <h2 class="card-title">Εφαρμογή</h2>
    <div class="setting-row"><span>Έκδοση</span><span class="muted">${esc(APP_VERSION)}</span></div>
    <p class="small muted">Οι ενημερώσεις κατεβαίνουν αυτόματα στο παρασκήνιο· όταν υπάρχει νέα έκδοση θα δεις ειδοποίηση. Τα δεδομένα σου μένουν ανέπαφα.</p>
    <button class="btn full" data-action="check-update">Έλεγχος για ενημέρωση</button>
  </section>

  <section class="card">
    <button class="btn danger full" data-action="wipe">Διαγραφή όλων των δεδομένων</button>
  </section>`;
}

async function fillStorageStatus() {
  const el = $('#persistStatus');
  if (!el) return;
  try {
    const persisted = await navigator.storage?.persisted?.();
    el.textContent = persisted ? 'ναι ✅' : navigator.standalone === false ? 'όχι — εγκατάστησε την εφαρμογή στην οθόνη Αφετηρίας' : 'όχι (ο browser μπορεί να καθαρίσει δεδομένα — κράτα αντίγραφο)';
  } catch {
    el.textContent = 'άγνωστο';
  }
}

// ---------- view actions ----------

const actions = {
  'open-purchase': (el) => {
    const p = P().find((x) => x.id === el.dataset.id);
    if (p) openEditor(p);
  },
  add: () => openEditor(),
  goto: (el) => go(el.dataset.tab),
  'stats-kind': (el) => {
    Object.assign(state.stats, { kind: el.dataset.kind, ref: L.today(), sel: null });
    render();
  },
  'stats-shift': (el) => {
    state.stats.ref = L.shiftPeriod(state.stats.kind, state.stats.ref, Number(el.dataset.dir));
    state.stats.sel = null;
    render();
  },
  'stats-mode': (el) => {
    state.stats.mode = el.dataset.mode;
    render();
  },
  'stats-cat': (el) => {
    state.stats.cat = state.stats.cat === el.dataset.cat ? null : el.dataset.cat;
    state.stats.sel = null;
    render();
  },
  'stats-bar': (el) => {
    const i = Number(el.dataset.i);
    state.stats.sel = state.stats.sel === i ? null : i;
    render();
  },
  'edit-cat': (el) => openCategoryEditor(C().find((c) => c.id === el.dataset.id)),
  'new-cat': () => openCategoryEditor(null),
  'test-paste': async () => {
    const tx = await readClipboardTransaction();
    if (tx) toast(`Βρέθηκε: ${money(tx.cents)}${tx.merchant ? ` · ${tx.merchant}` : ''}`);
  },
  'enable-enc': enableEncryption,
  'change-pass': changePasscode,
  'disable-enc': disableEncryption,
  'lock-now': lockNow,
  export: exportBackup,
  'check-update': checkForUpdate,
  wipe: async () => {
    if (!confirm('Θα διαγραφούν οριστικά όλες οι αγορές, κατηγορίες και ρυθμίσεις από αυτή τη συσκευή. Συνέχεια;')) return;
    if (!confirm('Τελευταία ευκαιρία: έχεις αντίγραφο ασφαλείας;\nΠάτα OK για οριστική διαγραφή.')) return;
    await saveChain;
    await db.clear();
    try { localStorage.clear(); } catch { /* ignore */ }
    location.reload();
  },
};

const changes = {
  budget: (el) => {
    const v = el.value.trim();
    const cents = v === '' ? null : L.toCents(v);
    if (cents != null && !(cents >= 0)) {
      toast('Μη έγκυρο ποσό');
      el.value = L.centsToInput(S().budgets[el.dataset.kind]);
      return;
    }
    S().budgets[el.dataset.kind] = cents;
    el.value = L.centsToInput(cents);
    save();
    toast('Αποθηκεύτηκε');
  },
  weekstart: (el) => {
    S().weekStart = Number(el.value);
    save();
  },
  autolock: (el) => {
    S().autoLockSec = Number(el.value);
    save();
  },
  'hist-cat': (el) => {
    state.history.cat = el.value;
    refreshHistory();
  },
  import: (el) => {
    const file = el.files?.[0];
    el.value = '';
    if (file) importBackup(file);
  },
};

const inputs = {
  'hist-q': (el) => {
    state.history.q = el.value;
    refreshHistory();
  },
};

function refreshHistory() {
  const list = $('#historyList');
  if (!list) return;
  list.innerHTML = historyList();
  applyStyles(list);
}

// ---------- sheets (modal dialogs) ----------

function openSheet(html, mount, onClose) {
  const d = $('#sheet');
  if (d.open) d.close();
  d.innerHTML = html;
  applyStyles(d);
  d.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => closeSheet()));
  d.onclose = () => {
    d.innerHTML = '';
    onClose?.();
  };
  d.showModal();
  mount?.(d);
}

function closeSheet() {
  const d = $('#sheet');
  if (d.open) d.close();
}

function askPasscode({ title, message = '', confirmNew = false }) {
  return new Promise((resolve) => {
    let result = null;
    openSheet(`<form class="sheet-form small-sheet" novalidate>
      <header class="sheet-head"><button type="button" class="link" data-close>Άκυρο</button><h2>${esc(title)}</h2><button type="submit" class="link strong">OK</button></header>
      <div class="sheet-body">
        ${message ? `<p class="small">${esc(message)}</p>` : ''}
        <label class="field"><span>Κωδικός</span><input name="p1" type="password" autocomplete="${confirmNew ? 'new-password' : 'current-password'}" required></label>
        ${confirmNew ? `<label class="field"><span>Επανάληψη κωδικού</span><input name="p2" type="password" autocomplete="new-password" required></label>
          <label class="check"><input type="checkbox" name="numeric"> Μόνο αριθμοί (αριθμητικό πληκτρολόγιο)</label>
          <p class="muted small">Τουλάχιστον 6 χαρακτήρες. Όσο μεγαλύτερος, τόσο ασφαλέστερος. Δεν ανακτάται αν τον ξεχάσεις.</p>` : ''}
        <p class="error" id="passErr"></p>
      </div></form>`, (d) => {
      const f = d.querySelector('form');
      const err = d.querySelector('#passErr');
      if (confirmNew) {
        f.numeric.addEventListener('change', () => {
          const mode = f.numeric.checked ? 'numeric' : 'text';
          f.p1.inputMode = mode;
          f.p2.inputMode = mode;
        });
      }
      f.p1.focus();
      f.addEventListener('submit', (e) => {
        e.preventDefault();
        const p1 = f.p1.value;
        if (confirmNew) {
          if (p1.length < 6) { err.textContent = 'Τουλάχιστον 6 χαρακτήρες.'; return; }
          if (f.numeric.checked && !/^\d+$/.test(p1)) { err.textContent = 'Μόνο αριθμοί, όπως επέλεξες.'; return; }
          if (p1 !== f.p2.value) { err.textContent = 'Οι κωδικοί δεν ταιριάζουν.'; return; }
        } else if (!p1) return;
        result = { pass: p1, numeric: confirmNew ? f.numeric.checked : undefined };
        closeSheet();
      });
    }, () => resolve(result));
  });
}

// ---------- purchase editor ----------

function rememberedItems() {
  const m = new Map();
  for (const p of [...P()].sort(byNewest)) {
    for (const i of p.items) {
      const k = norm(i.name);
      if (!m.has(k)) m.set(k, { name: i.name, cat: i.cat, cents: i.cents, days: i.days });
    }
  }
  return m;
}

function guessCat(store) {
  const s = norm(store);
  if (!s) return 'other';
  const past = [...P()].sort(byNewest).find((p) => norm(p.store) === s);
  if (past) return past.items[0].cat;
  const raw = String(store).toLowerCase();
  for (const [re, cat] of MERCHANT_HINTS) if (re.test(raw) && C().some((c) => c.id === cat)) return cat;
  return 'other';
}

const catOptions = (sel) => C().map((c) => `<option value="${esc(c.id)}" ${c.id === sel ? 'selected' : ''}>${esc(c.emoji)} ${esc(c.name)}</option>`).join('');

function daysOptions(sel) {
  const list = DAY_CHOICES.includes(sel) ? DAY_CHOICES : [...DAY_CHOICES, sel].sort((a, b) => a - b);
  return list.map((n) => `<option value="${n}" ${n === sel ? 'selected' : ''}>${n === 1 ? 'Μόνο αυτή τη μέρα' : `Για ${n} ημέρες`}</option>`).join('');
}

function itemRow(it) {
  return `<div class="item" data-id="${esc(it.id)}">
    <div class="item-top">
      <input class="i-name" list="dl-items" value="${esc(it.name)}" placeholder="Προϊόν (π.χ. Γάλα)" autocomplete="off" aria-label="Προϊόν">
      <span class="money-input"><input class="i-price" inputmode="decimal" value="${L.centsToInput(it.cents)}" placeholder="0,00" autocomplete="off" aria-label="Τιμή"><span>€</span></span>
      <button type="button" class="icon-btn i-remove" aria-label="Αφαίρεση προϊόντος">×</button>
    </div>
    <div class="item-bottom">
      <select class="i-cat" aria-label="Κατηγορία">${catOptions(it.cat)}</select>
      <select class="i-days" aria-label="Κατανομή σε ημέρες">${daysOptions(it.days)}</select>
    </div>
    <div class="item-hint"></div>
  </div>`;
}

function openEditor(existing = null, prefill = {}) {
  const draft = existing ? structuredClone(existing) : {
    id: uid(),
    date: prefill.date && isISODate(prefill.date) ? prefill.date : L.today(),
    store: prefill.store || '',
    note: '',
    source: prefill.source || 'manual',
    createdAt: Date.now(),
    items: [],
  };
  let expected = prefill.cents ?? null; // amount reported by Apple Pay, to help splitting into items
  const newItem = (cat = guessCat(draft.store), cents = null) => ({ id: uid(), name: '', cents, cat, days: 1 });
  if (!draft.items.length) draft.items.push(newItem(guessCat(draft.store), prefill.cents ?? null));

  const memory = rememberedItems();
  const stores = [...new Set([...P()].sort(byNewest).map((p) => p.store).filter(Boolean))].slice(0, 200);

  openSheet(`<form class="sheet-form" id="editor" novalidate>
    <header class="sheet-head">
      <button type="button" class="link" data-close>Άκυρο</button>
      <h2>${existing ? 'Επεξεργασία' : 'Νέα αγορά'}</h2>
      <button type="submit" class="link strong">Αποθήκευση</button>
    </header>
    <div class="sheet-body">
      ${existing ? '' : `<button type="button" class="btn ghost full" id="pasteTx">${ICON.apple} Επικόλληση από Apple Pay</button>`}
      <div class="field-row">
        <label class="field"><span>Ημερομηνία</span><input type="date" name="date" value="${draft.date}" required></label>
        <label class="field grow"><span>Κατάστημα</span><input name="store" list="dl-stores" value="${esc(draft.store)}" placeholder="π.χ. Lidl" autocomplete="off"></label>
      </div>
      <datalist id="dl-stores">${stores.map((s) => `<option value="${esc(s)}"></option>`).join('')}</datalist>
      <datalist id="dl-items">${[...memory.values()].slice(0, 300).map((i) => `<option value="${esc(i.name)}"></option>`).join('')}</datalist>
      <div class="section-title">Προϊόντα</div>
      <div id="items"></div>
      <button type="button" class="btn ghost full" id="addItem">+ Προσθήκη προϊόντος</button>
      <div class="total-box" id="totalBox"></div>
      <label class="field"><span>Σημείωση</span><textarea name="note" rows="2" placeholder="Προαιρετικό">${esc(draft.note)}</textarea></label>
      ${existing ? '<button type="button" class="btn danger full" id="delPurchase">Διαγραφή αγοράς</button>' : ''}
    </div>
  </form>`, (d) => {
    const form = d.querySelector('#editor');
    const itemsEl = form.querySelector('#items');
    const totalBox = form.querySelector('#totalBox');

    const readItems = () => {
      draft.items = [...itemsEl.querySelectorAll('.item')].map((row) => ({
        id: row.dataset.id,
        name: row.querySelector('.i-name').value.trim(),
        cents: L.toCents(row.querySelector('.i-price').value),
        cat: row.querySelector('.i-cat').value,
        days: Number(row.querySelector('.i-days').value) || 1,
      }));
    };

    const update = () => {
      readItems();
      const date = form.date.value || L.today();
      let total = 0;
      itemsEl.querySelectorAll('.item').forEach((row, i) => {
        const it = draft.items[i];
        const ok = it.cents > 0;
        if (ok) total += it.cents;
        row.querySelector('.item-hint').textContent = ok && it.days > 1
          ? `≈ ${money(Math.round(it.cents / it.days))} την ημέρα · ${L.shortDate(date)} – ${L.shortDate(L.addDays(date, it.days - 1))}`
          : '';
        const priceText = row.querySelector('.i-price').value.trim();
        row.classList.toggle('invalid', priceText !== '' && !ok);
      });
      let html = `<span>Σύνολο</span><strong>${money(total)}</strong>`;
      if (expected != null && expected !== total) {
        const diff = expected - total;
        html += `<div class="diff">Apple Pay: ${money(expected)} · ${diff > 0 ? `μένουν ${money(diff)} για κατανομή` : `υπέρβαση κατά ${money(-diff)}`}</div>`;
      }
      totalBox.innerHTML = html;
    };

    const renderItems = () => {
      itemsEl.innerHTML = draft.items.map(itemRow).join('');
      update();
    };

    itemsEl.addEventListener('input', update);
    itemsEl.addEventListener('change', (e) => {
      if (e.target.classList.contains('i-name')) {
        const known = memory.get(norm(e.target.value));
        const row = e.target.closest('.item');
        if (known) {
          row.querySelector('.i-cat').value = C().some((c) => c.id === known.cat) ? known.cat : 'other';
          const price = row.querySelector('.i-price');
          if (!price.value.trim()) price.value = L.centsToInput(known.cents);
          const daysSel = row.querySelector('.i-days');
          if (daysSel.value === '1' && known.days > 1) {
            daysSel.innerHTML = daysOptions(known.days);
          }
        }
      }
      update();
    });
    itemsEl.addEventListener('click', (e) => {
      const btn = e.target.closest('.i-remove');
      if (!btn) return;
      readItems();
      draft.items = draft.items.filter((i) => i.id !== btn.closest('.item').dataset.id);
      if (!draft.items.length) draft.items.push(newItem());
      renderItems();
    });
    form.querySelector('#addItem').addEventListener('click', () => {
      readItems();
      const last = draft.items[draft.items.length - 1];
      draft.items.push(newItem(last?.cat || guessCat(form.store.value)));
      renderItems();
      itemsEl.querySelector('.item:last-child .i-name').focus();
    });
    form.store.addEventListener('change', () => {
      readItems();
      const cat = guessCat(form.store.value);
      let changed = false;
      for (const it of draft.items) {
        if (!it.name && it.cat === 'other' && cat !== 'other') { it.cat = cat; changed = true; }
      }
      if (changed) renderItems();
    });
    form.date.addEventListener('change', update);

    form.querySelector('#pasteTx')?.addEventListener('click', async () => {
      const tx = await readClipboardTransaction();
      if (!tx) return;
      readItems();
      if (tx.merchant && !form.store.value.trim()) form.store.value = tx.merchant;
      expected = tx.cents;
      draft.source = 'applepay';
      const cat = guessCat(form.store.value);
      const empty = draft.items.length === 1 && !(draft.items[0].cents > 0);
      if (empty) {
        draft.items[0].cents = tx.cents;
        if (draft.items[0].cat === 'other') draft.items[0].cat = cat;
      }
      renderItems();
      toast(`Apple Pay: ${money(tx.cents)}${tx.merchant ? ` · ${tx.merchant}` : ''}`);
    });

    form.querySelector('#delPurchase')?.addEventListener('click', async () => {
      if (!confirm('Διαγραφή αυτής της αγοράς;')) return;
      state.data.purchases = P().filter((p) => p.id !== draft.id);
      await save();
      closeSheet();
      render();
      toast('Διαγράφηκε');
    });

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      readItems();
      const date = form.date.value;
      if (!isISODate(date)) { toast('Διάλεξε ημερομηνία'); return; }
      const rows = draft.items.filter((i) => i.name || !Number.isNaN(i.cents));
      if (rows.some((i) => !(i.cents > 0))) { toast('Έλεγξε τις τιμές των προϊόντων'); return; }
      if (!rows.length) { toast('Πρόσθεσε τουλάχιστον ένα προϊόν με τιμή'); return; }
      const store = form.store.value.trim().slice(0, 120);
      const purchase = {
        ...draft,
        date,
        store,
        note: form.note.value.trim().slice(0, 1000),
        updatedAt: Date.now(),
        items: rows.map((i) => ({ ...i, name: (i.name || store || catById(i.cat).name).slice(0, 120) })),
      };
      const idx = P().findIndex((p) => p.id === purchase.id);
      if (idx >= 0) P()[idx] = purchase;
      else P().push(purchase);
      await save();
      closeSheet();
      render();
      toast(idx >= 0 ? 'Ενημερώθηκε' : 'Αποθηκεύτηκε');
    });

    renderItems();
  });
}

async function readClipboardTransaction() {
  let text;
  try {
    text = await navigator.clipboard.readText();
  } catch {
    toast('Δεν δόθηκε πρόσβαση στο πρόχειρο');
    return null;
  }
  const tx = L.parseTransaction(text);
  if (!tx) toast('Δεν βρέθηκε ποσό στο πρόχειρο');
  return tx;
}

function handleUrlParams() {
  const params = new URLSearchParams(location.search);
  if (!params.has('amount') && !params.has('merchant') && !params.has('add')) return;
  const cents = params.has('amount') ? L.toCents(params.get('amount')) : null;
  history.replaceState(null, '', location.pathname);
  openEditor(null, {
    cents: cents != null && cents > 0 ? cents : null,
    store: (params.get('merchant') || '').slice(0, 120),
    date: params.get('date') || undefined,
    source: params.has('amount') ? 'applepay' : 'manual',
  });
}

// ---------- category editor ----------

function openCategoryEditor(cat) {
  const isNew = !cat;
  const c = cat ? { ...cat } : { id: uid(), name: '', emoji: '🏷️', color: '#0ea5e9', budget: null };
  openSheet(`<form class="sheet-form small-sheet" novalidate>
    <header class="sheet-head"><button type="button" class="link" data-close>Άκυρο</button>
      <h2>${isNew ? 'Νέα κατηγορία' : 'Κατηγορία'}</h2><button type="submit" class="link strong">Αποθήκευση</button></header>
    <div class="sheet-body">
      <div class="field-row">
        <label class="field emoji-field"><span>Εικονίδιο</span><input name="emoji" value="${esc(c.emoji)}" autocomplete="off"></label>
        <label class="field grow"><span>Όνομα</span><input name="name" value="${esc(c.name)}" required autocomplete="off"></label>
        <label class="field"><span>Χρώμα</span><input name="color" type="color" value="${esc(c.color)}"></label>
      </div>
      <label class="field"><span>Μηνιαίο budget κατηγορίας (προαιρετικό)</span>
        <span class="money-input"><input name="budget" inputmode="decimal" value="${L.centsToInput(c.budget)}" placeholder="—"><span>€</span></span></label>
      ${!isNew && c.id !== 'other' ? '<button type="button" class="btn danger full" id="delCat">Διαγραφή κατηγορίας</button>' : ''}
    </div></form>`, (d) => {
    const f = d.querySelector('form');
    if (isNew) f.name.focus();
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = f.name.value.trim().slice(0, 60);
      if (!name) { toast('Δώσε όνομα'); return; }
      const b = f.budget.value.trim();
      const budget = b === '' ? null : L.toCents(b);
      if (budget != null && !(budget >= 0)) { toast('Μη έγκυρο budget'); return; }
      const emoji = firstGrapheme(f.emoji.value.trim()) || '•';
      Object.assign(c, { name, emoji, color: isHex(f.color.value) ? f.color.value : c.color, budget });
      if (isNew) C().push(c);
      else C()[C().findIndex((x) => x.id === c.id)] = c;
      await save();
      closeSheet();
      render();
    });
    d.querySelector('#delCat')?.addEventListener('click', async () => {
      const used = P().reduce((n, p) => n + p.items.filter((i) => i.cat === c.id).length, 0);
      if (!confirm(used ? `Η κατηγορία χρησιμοποιείται σε ${used} προϊόντα, που θα μεταφερθούν στα «Άλλα». Διαγραφή;` : 'Διαγραφή κατηγορίας;')) return;
      for (const p of P()) for (const i of p.items) if (i.cat === c.id) i.cat = 'other';
      state.data.categories = C().filter((x) => x.id !== c.id);
      if (state.stats.cat === c.id) state.stats.cat = null;
      await save();
      closeSheet();
      render();
    });
  });
}

function firstGrapheme(s) {
  if (!s) return '';
  if (typeof Intl.Segmenter === 'function') return [...new Intl.Segmenter().segment(s)][0]?.segment || '';
  return [...s][0];
}

// ---------- encryption management ----------

async function verifyPasscode(pass) {
  try {
    const key = await deriveKey(pass, state.meta.salt, state.meta.iterations);
    await decryptJSON(key, await db.get('data'));
    return true;
  } catch {
    return false;
  }
}

async function setPasscode(pass, numeric) {
  const salt = randomSalt();
  const key = await deriveKey(pass, salt);
  const meta = { schema: SCHEMA, encrypted: true, salt, iterations: PBKDF2_ITERATIONS, numeric: !!numeric };
  await writeDataAndMeta(await encryptJSON(key, state.data), meta);
  state.key = key;
  state.meta = meta;
}

async function enableEncryption() {
  const r = await askPasscode({ title: 'Νέος κωδικός', confirmNew: true });
  if (!r) return;
  toast('Κρυπτογράφηση…');
  await setPasscode(r.pass, r.numeric);
  render();
  toast('🔒 Τα δεδομένα κρυπτογραφήθηκαν');
}

async function changePasscode() {
  const cur = await askPasscode({ title: 'Τρέχων κωδικός' });
  if (!cur) return;
  if (!(await verifyPasscode(cur.pass))) { toast('Λάθος κωδικός'); return; }
  const r = await askPasscode({ title: 'Νέος κωδικός', confirmNew: true });
  if (!r) return;
  await setPasscode(r.pass, r.numeric);
  render();
  toast('Ο κωδικός άλλαξε');
}

async function disableEncryption() {
  const cur = await askPasscode({ title: 'Επιβεβαίωση κωδικού', message: 'Τα δεδομένα θα αποθηκεύονται χωρίς κρυπτογράφηση.' });
  if (!cur) return;
  if (!(await verifyPasscode(cur.pass))) { toast('Λάθος κωδικός'); return; }
  const meta = { schema: SCHEMA, encrypted: false };
  await writeDataAndMeta(structuredClone(state.data), meta);
  state.key = null;
  state.meta = meta;
  render();
  toast('Η κρυπτογράφηση απενεργοποιήθηκε');
}

// ---------- backup ----------

async function exportBackup() {
  const exportedAt = new Date().toISOString();
  let payload;
  if (state.meta.encrypted) {
    const blob = await encryptJSON(state.key, state.data);
    payload = { app: 'spending-app', format: 1, encrypted: true, salt: state.meta.salt, iterations: state.meta.iterations, ...blob, exportedAt };
  } else {
    payload = { app: 'spending-app', format: 1, encrypted: false, data: state.data, exportedAt };
  }
  const name = `spending-backup-${L.today()}.json`;
  const file = new File([JSON.stringify(payload)], name, { type: 'application/json' });
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: name });
      return;
    } catch (e) {
      if (e.name === 'AbortError') return;
    }
  }
  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

async function importBackup(file) {
  let obj;
  try {
    if (file.size > 50 * 1024 * 1024) throw new Error('too big');
    obj = JSON.parse(await file.text());
  } catch {
    toast('Μη έγκυρο αρχείο');
    return;
  }
  if (obj?.app !== 'spending-app') { toast('Δεν είναι αντίγραφο αυτής της εφαρμογής'); return; }
  let data;
  if (obj.encrypted) {
    const r = await askPasscode({ title: 'Κωδικός αντιγράφου', message: 'Το αντίγραφο είναι κρυπτογραφημένο. Βάλε τον κωδικό που είχες όταν το δημιούργησες.' });
    if (!r) return;
    try {
      const iterations = int(obj.iterations, 100_000, 10_000_000, PBKDF2_ITERATIONS);
      data = await decryptJSON(await deriveKey(r.pass, obj.salt, iterations), obj);
    } catch {
      toast('Λάθος κωδικός ή κατεστραμμένο αρχείο');
      return;
    }
  } else {
    data = obj.data;
  }
  const clean = sanitize(data);
  if (!confirm(`Το αντίγραφο έχει ${clean.purchases.length} αγορές. Θα αντικαταστήσει τα τρέχοντα δεδομένα. Συνέχεια;`)) return;
  state.data = clean;
  moneyFmt = null;
  await save();
  render();
  toast('Η επαναφορά ολοκληρώθηκε');
}

// ---------- updates (service worker) ----------

let swReg = null;

function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloading) return;
    reloading = true;
    location.reload();
  });
  navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' }).then((reg) => {
    swReg = reg;
    if (reg.waiting && navigator.serviceWorker.controller) showUpdateBanner(reg.waiting);
    reg.addEventListener('updatefound', () => {
      const w = reg.installing;
      w?.addEventListener('statechange', () => {
        if (w.state === 'installed' && navigator.serviceWorker.controller) showUpdateBanner(w);
      });
    });
    // Look for a new version whenever the app comes back to the foreground, and hourly.
    document.addEventListener('visibilitychange', () => { if (!document.hidden) reg.update().catch(() => {}); });
    setInterval(() => reg.update().catch(() => {}), 60 * 60 * 1000);
  }).catch((err) => console.warn('SW registration failed', err));
}

function showUpdateBanner(worker) {
  const banner = $('#updateBanner');
  banner.hidden = false;
  $('#updateBtn').onclick = async () => {
    $('#updateBtn').disabled = true;
    await saveChain; // never reload with unsaved changes
    worker.postMessage({ type: 'SKIP_WAITING' });
  };
}

async function checkForUpdate() {
  if (!swReg) { toast('Οι ενημερώσεις δεν υποστηρίζονται εδώ'); return; }
  toast('Έλεγχος…');
  try {
    await swReg.update();
    if (!swReg.installing && !swReg.waiting) toast('Έχεις την τελευταία έκδοση ✅');
  } catch {
    toast('Χωρίς σύνδεση — δοκίμασε αργότερα');
  }
}

boot().catch((err) => {
  console.error(err);
  document.body.textContent = 'Σφάλμα κατά την εκκίνηση. Δοκίμασε να ανανεώσεις τη σελίδα.';
});
