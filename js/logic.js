// Pure helpers: dates, money, allocation of item costs across days, periods.
// No DOM access here so it can be unit-tested with Node.

const pad = (n) => String(n).padStart(2, '0');

export const iso = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

// Noon avoids DST edge cases when adding days.
export const parse = (s) => {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, m - 1, d, 12);
};

export const today = () => iso(new Date());

export const addDays = (s, n) => {
  const d = parse(s);
  d.setDate(d.getDate() + n);
  return iso(d);
};

// b - a in whole days
export const daysBetween = (a, b) => Math.round((parse(b) - parse(a)) / 86400000);

export const minDate = (a, b) => (a < b ? a : b);
export const maxDate = (a, b) => (a > b ? a : b);

export const MONTHS = ['Ιανουάριος', 'Φεβρουάριος', 'Μάρτιος', 'Απρίλιος', 'Μάιος', 'Ιούνιος',
  'Ιούλιος', 'Αύγουστος', 'Σεπτέμβριος', 'Οκτώβριος', 'Νοέμβριος', 'Δεκέμβριος'];
export const MONTHS_SHORT = ['Ιαν', 'Φεβ', 'Μαρ', 'Απρ', 'Μαΐ', 'Ιουν', 'Ιουλ', 'Αυγ', 'Σεπ', 'Οκτ', 'Νοε', 'Δεκ'];
export const WEEKDAYS = ['Κυρ', 'Δευ', 'Τρί', 'Τετ', 'Πέμ', 'Παρ', 'Σάβ'];

export function shortDate(s, withYear = false) {
  const d = parse(s);
  const base = `${WEEKDAYS[d.getDay()]} ${d.getDate()} ${MONTHS_SHORT[d.getMonth()]}`;
  return withYear ? `${base} ${d.getFullYear()}` : base;
}

export function dayLabel(s, ref = today()) {
  const diff = daysBetween(s, ref);
  if (diff === 0) return 'Σήμερα';
  if (diff === 1) return 'Χθες';
  if (diff === -1) return 'Αύριο';
  return shortDate(s, s.slice(0, 4) !== ref.slice(0, 4));
}

// ---------- money ----------

// Accepts "12,50", "12.50", "€ 1.234,56", "1,234.56", "EUR 3.2" → integer cents (NaN if invalid)
export function toCents(input) {
  if (typeof input === 'number') return Number.isFinite(input) ? Math.round(input * 100) : NaN;
  let s = String(input ?? '').replace(/[^\d,.-]/g, '');
  if (!/\d/.test(s)) return NaN;
  const lastComma = s.lastIndexOf(',');
  const lastDot = s.lastIndexOf('.');
  if (lastComma > lastDot) s = s.replace(/\./g, '').replace(',', '.');
  else s = s.replace(/,/g, '');
  const v = Number.parseFloat(s);
  return Number.isFinite(v) ? Math.round(v * 100) : NaN;
}

export const centsToInput = (c) => (c == null || Number.isNaN(c) ? '' : (c / 100).toFixed(2).replace('.', ','));

// ---------- allocation ----------

// Splits cents over n days; the remainder goes to the first days so the sum is exact.
export function splitCents(cents, n) {
  n = Math.max(1, Math.floor(n) || 1);
  const base = Math.trunc(cents / n);
  let rem = cents - base * n;
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push(base + (rem > 0 ? 1 : 0));
    if (rem > 0) rem--;
  }
  return out;
}

// mode 'spread': each item's cost is spread over item.days starting on the purchase date.
// mode 'paid': the full cost lands on the purchase date.
export function allocations(purchases, mode = 'spread') {
  const out = [];
  for (const p of purchases) {
    for (const it of p.items) {
      const n = mode === 'spread' ? Math.max(1, it.days || 1) : 1;
      splitCents(it.cents, n).forEach((cents, i) => {
        const a = { date: addDays(p.date, i), cents, cat: it.cat, name: it.name, pid: p.id };
        if (p.unexpected) a.unexpected = true;
        out.push(a);
      });
    }
  }
  return out;
}

// Unexpected expenses come out of their own monthly fund, not the regular budgets.
export const regular = (purchases) => purchases.filter((p) => !p.unexpected);

export const inRange = (a, start, end) => a.date >= start && a.date <= end;
export const sum = (arr) => arr.reduce((s, a) => s + a.cents, 0);

// ---------- periods ----------

export function period(kind, ref, weekStart = 1) {
  const d = parse(ref);
  switch (kind) {
    case 'day':
      return { start: ref, end: ref };
    case 'week': {
      const start = addDays(ref, -((d.getDay() - weekStart + 7) % 7));
      return { start, end: addDays(start, 6) };
    }
    case 'month':
      return {
        start: iso(new Date(d.getFullYear(), d.getMonth(), 1, 12)),
        end: iso(new Date(d.getFullYear(), d.getMonth() + 1, 0, 12)),
      };
    case 'year':
      return { start: `${d.getFullYear()}-01-01`, end: `${d.getFullYear()}-12-31` };
    default:
      throw new Error(`unknown period ${kind}`);
  }
}

export function shiftPeriod(kind, ref, dir) {
  const d = parse(ref);
  if (kind === 'week') return addDays(ref, 7 * dir);
  if (kind === 'month') return iso(new Date(d.getFullYear(), d.getMonth() + dir, 1, 12));
  if (kind === 'year') return iso(new Date(d.getFullYear() + dir, 0, 1, 12));
  return addDays(ref, dir);
}

export function periodLabel(kind, start, end) {
  const s = parse(start);
  const e = parse(end);
  if (kind === 'day') return shortDate(start, true);
  if (kind === 'month') return `${MONTHS[s.getMonth()]} ${s.getFullYear()}`;
  if (kind === 'year') return String(s.getFullYear());
  const sm = MONTHS_SHORT[s.getMonth()];
  const em = MONTHS_SHORT[e.getMonth()];
  return sm === em
    ? `${s.getDate()}–${e.getDate()} ${em} ${e.getFullYear()}`
    : `${s.getDate()} ${sm} – ${e.getDate()} ${em} ${e.getFullYear()}`;
}

// How much can be spent today so that a period budget is respected.
// Spending before today and amounts already allocated to later days are subtracted,
// then the rest is shared equally among the remaining days (today included).
export function dailyAllowance(budget, allocs, kind, ref, weekStart = 1) {
  const { start, end } = period(kind, ref, weekStart);
  let before = 0;
  let after = 0;
  for (const a of allocs) {
    if (a.date >= start && a.date < ref) before += a.cents;
    else if (a.date > ref && a.date <= end) after += a.cents;
  }
  const daysLeft = daysBetween(ref, end) + 1;
  return Math.floor((budget - before - after) / daysLeft);
}

// Days with a daily budget before this date (the feature's release) are not counted,
// so earlier days without a budget do not show up as savings.
export const CARRY_START = '2026-10-11';

// Daily budget minus actual spending, from the start of the month (or `since`) up to yesterday.
// Positive = left unspent (carried into today), negative = overspent.
export function dayBalance(budget, allocs, ref, since = CARRY_START) {
  const start = maxDate(maxDate(since || CARRY_START, CARRY_START), ref.slice(0, 8) + '01');
  const end = addDays(ref, -1);
  if (start > end) return 0;
  let spent = 0;
  for (const a of allocs) if (a.date >= start && a.date <= end) spent += a.cents;
  return budget * (daysBetween(start, end) + 1) - spent;
}

// ---------- Apple Pay / clipboard parsing ----------

// Accepts text like "€12,50;Lidl", "Lidl\n12,50 €", "12.50 EUR | Shell"
export function parseTransaction(text) {
  if (!text) return null;
  const parts = String(text).split(/[;\n|]/).map((s) => s.trim()).filter(Boolean);
  let cents = NaN;
  let merchant = '';
  for (const p of parts) {
    const stripped = p.replace(/\b[A-Z]{3}\b|[€$£\s ]/g, '');
    if (Number.isNaN(cents) && /^-?[\d.,]+$/.test(stripped) && /\d/.test(stripped)) cents = toCents(stripped);
    else if (!merchant) merchant = p;
  }
  if (Number.isNaN(cents)) return null;
  return { cents: Math.abs(cents), merchant };
}

// ---------- category budgets ----------

// Sets a category's budget (cents per 'week' or 'month') and records the change.
// Returns false if nothing changed. Mutates `cat`.
export function setCategoryBudget(cat, cents, period, at = Date.now()) {
  period = period === 'week' ? 'week' : 'month';
  const cur = cat.budget ?? null;
  const curPeriod = cat.budgetPeriod === 'week' ? 'week' : 'month';
  if (cents === cur && (cents == null || period === curPeriod)) return false;
  cat.budgetHistory = [...(cat.budgetHistory || []),
    { at, from: cur, fromPeriod: cur == null ? null : curPeriod, to: cents, period }].slice(-200);
  cat.budget = cents;
  cat.budgetPeriod = period;
  return true;
}

// Times an existing budget was changed or removed (setting it the first time is not a change).
export const budgetChanges = (cat) => (cat.budgetHistory || []).filter((h) => h.from != null).length;

// Spending of every category that has a budget, within that category's current week or month.
export function categoryBudgets(categories, allocs, today, weekStart = 1) {
  return categories.filter((c) => c.budget != null).map((c) => {
    const { start, end } = period(c.budgetPeriod === 'week' ? 'week' : 'month', today, weekStart);
    let spent = 0;
    for (const a of allocs) if (a.cat === c.id && a.date >= start && a.date <= end) spent += a.cents;
    return { cat: c, start, end, budget: c.budget, spent };
  });
}

// ---------- sync: change stamps and merging ----------

// Stable JSON (sorted keys, undefined ≈ null) for comparing data from different devices.
export function canon(v) {
  if (Array.isArray(v)) return `[${v.map(canon).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v).sort().filter((k) => v[k] !== undefined && v[k] !== null)
      .map((k) => `${JSON.stringify(k)}:${canon(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v ?? null);
}

const stampOf = (p) => Math.max(p.updatedAt || 0, p.createdAt || 0);

// Marks what changed between the last saved data and the new data, so another device can tell
// which copy is newer: settings/categories get a timestamp, edited purchases get updatedAt and
// removed purchases are remembered in `deleted`. Mutates and returns `next`.
export function stampChanges(prev, next, now = Date.now()) {
  if (!prev) return next;
  if (canon(prev.settings) !== canon(next.settings)) next.settingsUpdatedAt = now;
  if (canon(prev.categories) !== canon(next.categories)) next.categoriesUpdatedAt = now;
  const before = new Map(prev.purchases.map((p) => [p.id, p]));
  const body = (p) => canon({ ...p, updatedAt: 0 });
  for (const p of next.purchases) {
    const q = before.get(p.id);
    if (!q || body(q) !== body(p)) p.updatedAt = now;
    before.delete(p.id);
  }
  next.deleted = { ...(next.deleted || {}) };
  for (const id of before.keys()) next.deleted[id] = now;
  return next;
}

// Combines this device's data with the account's data. Purchases merge one by one (newest edit
// wins, deletions win over older edits); settings and categories take the most recently changed
// copy. Ties go to the server copy, so a new device adopts the account's data.
export function mergeData(local, remote, now = Date.now()) {
  const deleted = { ...(remote.deleted || {}) };
  for (const [id, t] of Object.entries(local.deleted || {})) deleted[id] = Math.max(deleted[id] || 0, t);
  const byId = new Map(remote.purchases.map((p) => [p.id, p]));
  for (const p of local.purchases) {
    const r = byId.get(p.id);
    if (!r || stampOf(p) > stampOf(r)) byId.set(p.id, p);
  }
  const purchases = [...byId.values()].filter((p) => !((deleted[p.id] || 0) >= stampOf(p)));

  const localCats = (local.categoriesUpdatedAt || 0) > (remote.categoriesUpdatedAt || 0);
  const categories = [...(localCats ? local.categories : remote.categories)];
  // keep categories from the other side that merged purchases still use
  const used = new Set(purchases.flatMap((p) => p.items.map((i) => i.cat)));
  for (const c of localCats ? remote.categories : local.categories) {
    if (used.has(c.id) && !categories.some((x) => x.id === c.id)) categories.splice(Math.max(0, categories.length - 1), 0, c);
  }

  const yearAgo = now - 365 * 86400000;
  return {
    schema: Math.max(local.schema || 1, remote.schema || 1),
    settings: (local.settingsUpdatedAt || 0) > (remote.settingsUpdatedAt || 0) ? local.settings : remote.settings,
    settingsUpdatedAt: Math.max(local.settingsUpdatedAt || 0, remote.settingsUpdatedAt || 0),
    categories,
    categoriesUpdatedAt: Math.max(local.categoriesUpdatedAt || 0, remote.categoriesUpdatedAt || 0),
    purchases,
    deleted: Object.fromEntries(Object.entries(deleted).filter(([, t]) => t > yearAgo)),
  };
}
