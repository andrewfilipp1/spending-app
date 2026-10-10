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
        out.push({ date: addDays(p.date, i), cents, cat: it.cat, name: it.name, pid: p.id });
      });
    }
  }
  return out;
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
