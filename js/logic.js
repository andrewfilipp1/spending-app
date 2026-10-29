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
        if (p.offDaily) a.offDaily = true;
        out.push(a);
      });
    }
  }
  return out;
}

// Unexpected expenses come out of their own monthly fund, not the regular budgets.
export const regular = (purchases) => purchases.filter((p) => !p.unexpected);

// Categories with their own fund (e.g. weekly groceries) are kept out of the general
// day/week/month/year budgets; they count only against their category budget.
export function general(allocs, categories) {
  const own = new Set(categories.filter((c) => c.ownFund).map((c) => c.id));
  return own.size ? allocs.filter((a) => !own.has(a.cat)) : allocs;
}

// General payments (e.g. subscriptions) count in the week/month/year budgets but not in the daily
// limit: either the purchase is marked so, or its category is.
export function daily(allocs, categories) {
  const off = new Set(categories.filter((c) => c.offDaily).map((c) => c.id));
  return allocs.filter((a) => !a.offDaily && !off.has(a.cat));
}

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
// `paidToday`: today's general payments, which are already spent but not part of the daily limit.
export function dailyAllowance(budget, allocs, kind, ref, weekStart = 1, paidToday = 0) {
  const { start, end } = period(kind, ref, weekStart);
  let before = 0;
  let after = 0;
  for (const a of allocs) {
    if (a.date >= start && a.date < ref) before += a.cents;
    else if (a.date > ref && a.date <= end) after += a.cents;
  }
  const daysLeft = daysBetween(ref, end) + 1;
  return Math.floor((budget - before - after - paidToday) / daysLeft);
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

// ---------- item history ----------

// Key that ignores case, accents, final sigma, punctuation and extra spaces: "Γάλα  ", "γαλα" → "γαλα".
export const itemKey = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .replace(/ς/g, 'σ').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

// Every item name used so far, one per key: the most used spelling, with the latest price/category.
export function knownItems(purchases) {
  const map = new Map();
  const sorted = [...purchases].sort((a, b) => (a.date === b.date ? (b.createdAt || 0) - (a.createdAt || 0) : a.date < b.date ? 1 : -1));
  for (const p of sorted) {
    for (const i of p.items) {
      const key = itemKey(i.name);
      if (!key) continue;
      let k = map.get(key);
      if (!k) {
        k = { key, name: i.name, count: 0, spellings: {}, cat: i.cat, cents: i.cents, days: i.days, last: p.date };
        map.set(key, k);
      }
      k.count++;
      k.spellings[i.name] = (k.spellings[i.name] || 0) + 1;
    }
  }
  for (const k of map.values()) {
    // most used spelling; ties keep the newest (inserted first)
    k.name = Object.entries(k.spellings).reduce((best, e) => (e[1] > best[1] ? e : best))[0];
  }
  return [...map.values()].sort((a, b) => b.count - a.count || (a.last < b.last ? 1 : -1));
}

// Edit distance with swapped neighbours counting as one typo (optimal string alignment).
export function typoDistance(a, b, max = 2) {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev2 = null;
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
      if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1);
      cur.push(v);
      rowMin = Math.min(rowMin, v);
    }
    if (rowMin > max) return max + 1;
    prev2 = prev;
    prev = cur;
  }
  return prev[b.length];
}

// How many typos a name of this length may contain and still count as the same item.
const typoLimit = (n) => (n < 4 ? 0 : n < 8 ? 1 : 2);

// The known item this name means: { item, exact } or null.
// exact: same key (only the spelling differs). Otherwise a likely typo of a known item.
export function matchItem(name, known) {
  const key = itemKey(name);
  if (!key) return null;
  const same = known.find((k) => k.key === key);
  if (same) return { item: same, exact: true };
  const limit = typoLimit(key.length);
  let best = null;
  let bestD = limit + 1;
  for (const k of known) {
    if (typoLimit(k.key.length) === 0) continue;
    const d = typoDistance(key, k.key, limit);
    if (d < bestD || (d === bestD && best && k.count > best.count)) { best = k; bestD = d; }
  }
  return best && bestD <= limit ? { item: best, exact: false } : null;
}

// Groups of item names that are probably the same thing, to merge in the item history.
export function duplicateItems(known) {
  const groups = [];
  const used = new Set();
  for (const k of known) { // most used first, so it becomes the suggested name
    if (used.has(k.key)) continue;
    const others = Object.keys(k.spellings).filter((s) => s !== k.name);
    const similar = known.filter((o) => o !== k && !used.has(o.key) && typoLimit(o.key.length) > 0
      && typoDistance(k.key, o.key, Math.min(typoLimit(k.key.length), typoLimit(o.key.length))) <= Math.min(typoLimit(k.key.length), typoLimit(o.key.length)));
    if (!others.length && !similar.length) continue;
    used.add(k.key);
    for (const o of similar) used.add(o.key);
    const names = [...others, ...similar.flatMap((o) => Object.keys(o.spellings))];
    groups.push({ name: k.name, names, count: k.count + similar.reduce((s, o) => s + o.count, 0) });
  }
  return groups;
}

// Renames every item whose name is in `from` (exact spellings) to `to`. Returns how many changed.
export function renameItems(purchases, from, to) {
  const set = new Set(from);
  let n = 0;
  for (const p of purchases) {
    for (const i of p.items) {
      if (set.has(i.name) && i.name !== to) { i.name = to; n++; }
    }
  }
  return n;
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

// Lists merged record by record. Ids are unique across them, so they share `deleted`.
const RECORDS = ['purchases', 'meals', 'foods'];

// Marks what changed between the last saved data and the new data, so another device can tell
// which copy is newer: settings/categories/nutrition get a timestamp, edited records (purchases,
// meals, foods) get updatedAt and removed ones are remembered in `deleted`. Mutates and returns `next`.
export function stampChanges(prev, next, now = Date.now()) {
  if (!prev) return next;
  if (canon(prev.settings) !== canon(next.settings)) next.settingsUpdatedAt = now;
  if (canon(prev.categories) !== canon(next.categories)) next.categoriesUpdatedAt = now;
  if (canon(prev.nutrition) !== canon(next.nutrition)) next.nutritionUpdatedAt = now;
  next.deleted = { ...(next.deleted || {}) };
  const body = (p) => canon({ ...p, updatedAt: 0 });
  for (const list of RECORDS) {
    const before = new Map((prev[list] || []).map((p) => [p.id, p]));
    for (const p of next[list] || []) {
      const q = before.get(p.id);
      if (!q || body(q) !== body(p)) p.updatedAt = now;
      before.delete(p.id);
    }
    for (const id of before.keys()) next.deleted[id] = now;
  }
  return next;
}

// Combines this device's data with the account's data. Purchases, meals and foods merge one by one (newest edit
// wins, deletions win over older edits); settings and categories take the most recently changed
// copy, and so does nutrition. Ties go to the server copy, so a new device adopts the account's data.
export function mergeData(local, remote, now = Date.now()) {
  const deleted = { ...(remote.deleted || {}) };
  for (const [id, t] of Object.entries(local.deleted || {})) deleted[id] = Math.max(deleted[id] || 0, t);
  const records = (list) => {
    const byId = new Map((remote[list] || []).map((p) => [p.id, p]));
    for (const p of local[list] || []) {
      const r = byId.get(p.id);
      if (!r || stampOf(p) > stampOf(r)) byId.set(p.id, p);
    }
    return [...byId.values()].filter((p) => !((deleted[p.id] || 0) >= stampOf(p)));
  };
  const purchases = records('purchases');

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
    meals: records('meals'),
    foods: records('foods'),
    nutrition: (local.nutritionUpdatedAt || 0) > (remote.nutritionUpdatedAt || 0) ? local.nutrition : remote.nutrition,
    nutritionUpdatedAt: Math.max(local.nutritionUpdatedAt || 0, remote.nutritionUpdatedAt || 0),
    deleted: Object.fromEntries(Object.entries(deleted).filter(([, t]) => t > yearAgo)),
  };
}

// ---------- nutrition ----------

export const MEALS = [['breakfast', 'Πρωινό'], ['lunch', 'Μεσημεριανό'], ['dinner', 'Βραδινό'], ['snack', 'Σνακ']];
export const MACROS = ['protein', 'carbs', 'fat'];

const round1 = (x) => Math.round(x * 10) / 10;

// The meal of the day for a given time (default: now), for a new entry.
export function mealFor(hour = new Date().getHours()) {
  if (hour >= 5 && hour < 11) return 'breakfast';
  if (hour >= 12 && hour < 16) return 'lunch';
  if (hour >= 19 && hour < 23) return 'dinner';
  return 'snack';
}

// What `qty` servings of a library food add up to.
export function fromFood(food, qty = 1) {
  return {
    name: food.name, foodId: food.id, qty,
    kcal: Math.round(food.kcal * qty),
    protein: round1(food.protein * qty), carbs: round1(food.carbs * qty), fat: round1(food.fat * qty),
  };
}

// Totals of the meals eaten on `date`.
export function dayNutrition(meals, date) {
  const t = { kcal: 0, protein: 0, carbs: 0, fat: 0 };
  for (const m of meals) {
    if (m.date !== date) continue;
    t.kcal += m.kcal;
    for (const k of MACROS) t[k] += m[k];
  }
  for (const k of MACROS) t[k] = round1(t[k]);
  return t;
}

// The day's calorie goal. With health data (from the watch): a typical day's resting energy plus
// what was burned moving today, plus the adjustment (e.g. -400 to lose weight). Otherwise the fixed goal.
export function kcalGoal(nutrition, health) {
  if (nutrition?.useHealth && health?.restingKcal > 0) {
    return Math.max(0, Math.round(health.restingKcal + (health.activeKcal || 0) + (nutrition.kcalAdjust || 0)));
  }
  return nutrition?.kcalGoal ?? null;
}

// Library foods and earlier meals, most used first, for quick entry. Same names count once (newest wins).
export function recentFoods(meals, foods, limit = 20) {
  const byKey = new Map();
  for (const f of foods) byKey.set(itemKey(f.name), { ...fromFood(f), serving: f.serving, count: 0, last: '' });
  for (const m of [...meals].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))) {
    const k = itemKey(m.name);
    const e = byKey.get(k);
    if (e?.foodId) {
      e.count++;
      e.last = m.date;
    } else {
      byKey.set(k, { name: m.name, foodId: null, qty: 1, kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat,
        serving: '', count: (e?.count || 0) + 1, last: m.date });
    }
  }
  return [...byKey.values()].sort((a, b) => b.count - a.count || (a.last < b.last ? 1 : -1)).slice(0, limit);
}

// What food bought costs: per category, the linked items' cost against the meals eaten from them.
// An item eaten over several meals counts once.
export function foodCosts(meals, purchases) {
  const items = new Map();
  for (const p of purchases) for (const i of p.items) items.set(i.id, i);
  const byCat = new Map();
  const counted = new Set();
  for (const m of meals) {
    const i = m.itemId && items.get(m.itemId);
    if (!i) continue;
    const c = byCat.get(i.cat) || { cat: i.cat, cents: 0, kcal: 0, protein: 0 };
    if (!counted.has(i.id)) {
      counted.add(i.id);
      c.cents += i.cents;
    }
    c.kcal += m.kcal;
    c.protein += m.protein;
    byCat.set(i.cat, c);
  }
  return [...byCat.values()].map((c) => ({
    ...c,
    protein: round1(c.protein),
    per1000kcal: c.kcal > 0 ? Math.round((c.cents * 1000) / c.kcal) : null,
    per10gProtein: c.protein > 0 ? Math.round((c.cents * 10) / c.protein) : null,
  }));
}
