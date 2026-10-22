import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as L from '../js/logic.js';

test('toCents parses Greek and English formats', () => {
  assert.equal(L.toCents('12,50'), 1250);
  assert.equal(L.toCents('12.5'), 1250);
  assert.equal(L.toCents('€ 1.234,56'), 123456);
  assert.equal(L.toCents('1,234.56'), 123456);
  assert.equal(L.toCents('3'), 300);
  assert.ok(Number.isNaN(L.toCents('')));
  assert.ok(Number.isNaN(L.toCents('abc')));
});

test('splitCents keeps the exact total', () => {
  assert.deepEqual(L.splitCents(1000, 3), [334, 333, 333]);
  assert.deepEqual(L.splitCents(5, 1), [5]);
  assert.equal(L.splitCents(9999, 7).reduce((a, b) => a + b), 9999);
});

test('allocations spread items across days', () => {
  const purchases = [{ id: 'p', date: '2026-10-30', items: [
    { name: 'Κοτόπουλο', cents: 900, cat: 'groceries', days: 3 },
    { name: 'Καφές', cents: 250, cat: 'coffee', days: 1 },
  ] }];
  const spread = L.allocations(purchases, 'spread');
  assert.deepEqual(spread.map((a) => [a.date, a.cents]), [
    ['2026-10-30', 300], ['2026-10-31', 300], ['2026-11-01', 300], ['2026-10-30', 250],
  ]);
  const paid = L.allocations(purchases, 'paid');
  assert.equal(L.sum(paid.filter((a) => a.date === '2026-10-30')), 1150);
});

test('periods', () => {
  assert.deepEqual(L.period('week', '2026-10-10', 1), { start: '2026-10-05', end: '2026-10-11' }); // Saturday
  assert.deepEqual(L.period('week', '2026-10-11', 1), { start: '2026-10-05', end: '2026-10-11' }); // Sunday
  assert.deepEqual(L.period('week', '2026-10-11', 0), { start: '2026-10-11', end: '2026-10-17' });
  assert.deepEqual(L.period('month', '2026-02-15'), { start: '2026-02-01', end: '2026-02-28' });
  assert.deepEqual(L.period('year', '2026-06-01'), { start: '2026-01-01', end: '2026-12-31' });
  assert.equal(L.shiftPeriod('month', '2026-01-31', 1), '2026-02-01');
  assert.equal(L.addDays('2026-03-28', 2), '2026-03-30'); // across DST change
  assert.equal(L.periodLabel('month', '2026-10-01', '2026-10-31'), 'Οκτώβριος 2026');
});

test('dailyAllowance shares what is left of the budget over the remaining days', () => {
  // Monthly budget 310€ in October (31 days). On the 11th, 50€ spent before, 10€ already allocated to the 12th.
  const allocs = [
    { date: '2026-10-05', cents: 5000 },
    { date: '2026-10-12', cents: 1000 },
    { date: '2026-10-11', cents: 700 }, // today's spending does not reduce today's allowance
  ];
  const daysLeft = 21; // 11..31
  assert.equal(L.dailyAllowance(31000, allocs, 'month', '2026-10-11'), Math.floor((31000 - 5000 - 1000) / daysLeft));
});

test('parseTransaction reads Shortcuts clipboard text', () => {
  assert.deepEqual(L.parseTransaction('€12,50;Lidl'), { cents: 1250, merchant: 'Lidl' });
  assert.deepEqual(L.parseTransaction('Σκλαβενίτης\n7,30 €'), { cents: 730, merchant: 'Σκλαβενίτης' });
  assert.deepEqual(L.parseTransaction('12.50 EUR | Shell'), { cents: 1250, merchant: 'Shell' });
  assert.equal(L.parseTransaction('hello'), null);
  assert.equal(L.parseTransaction(''), null);
});

test('category budget history counts changes, not the first setting', () => {
  const c = { id: 'fuel' };
  assert.equal(L.setCategoryBudget(c, 20000, 'month', 1), true);
  assert.equal(L.budgetChanges(c), 0);
  assert.equal(L.setCategoryBudget(c, 20000, 'month', 2), false);
  L.setCategoryBudget(c, 25000, 'month', 3);
  L.setCategoryBudget(c, 6000, 'week', 4);
  L.setCategoryBudget(c, null, 'week', 5);
  assert.equal(L.budgetChanges(c), 3);
  assert.deepEqual(c.budgetHistory[2], { at: 4, from: 25000, fromPeriod: 'month', to: 6000, period: 'week' });
});

test('category budgets use their own period', () => {
  const cats = [{ id: 'fuel', budget: 5000, budgetPeriod: 'week' }, { id: 'groceries', budget: null }];
  const allocs = [{ date: '2026-10-05', cents: 3000, cat: 'fuel' }, { date: '2026-10-01', cents: 9000, cat: 'fuel' }];
  assert.deepEqual(L.categoryBudgets(cats, allocs, '2026-10-10', 1).map((s) => [s.cat.id, s.start, s.spent]), [['fuel', '2026-10-05', 3000]]);
});

const base = () => ({ schema: 2, settings: { budgets: { month: 1000 } }, categories: [{ id: 'other' }], purchases: [] });
const pur = (id, cents, extra = {}) => ({ id, date: '2026-10-10', createdAt: 1, items: [{ id: `i${id}`, name: id, cents, cat: 'other', days: 1 }], ...extra });

test('stampChanges marks edits, additions and deletions', () => {
  const prev = { ...base(), purchases: [pur('a', 100), pur('b', 200)] };
  const next = structuredClone(prev);
  next.purchases[0].items[0].cents = 150; // edit a
  next.purchases.splice(1, 1); // delete b
  next.purchases.push(pur('c', 300)); // add c
  next.settings.budgets.month = 2000;
  L.stampChanges(prev, next, 50);
  assert.deepEqual(next.purchases.map((p) => [p.id, p.updatedAt]), [['a', 50], ['c', 50]]);
  assert.deepEqual(next.deleted, { b: 50 });
  assert.equal(next.settingsUpdatedAt, 50);
  assert.equal(next.categoriesUpdatedAt, undefined);
});

test('mergeData keeps both sides changes and respects deletions', () => {
  const remote = { ...base(), purchases: [pur('a', 100, { updatedAt: 10 }), pur('b', 200), pur('d', 1, { updatedAt: 40 })],
    deleted: { x: 5 }, settingsUpdatedAt: 30, settings: { budgets: { month: 3000 } } };
  const local = { ...base(), purchases: [pur('a', 999, { updatedAt: 20 }), pur('c', 300, { updatedAt: 20 }), pur('d', 1, { updatedAt: 40 })],
    deleted: { b: 15, d: 30 }, settingsUpdatedAt: 20 };
  const m = L.mergeData(local, remote, 100);
  assert.deepEqual(m.purchases.map((p) => [p.id, p.items[0].cents]).sort(), [['a', 999], ['c', 300], ['d', 1]]);
  assert.equal(m.settings.budgets.month, 3000); // remote settings are newer
  assert.deepEqual(m.deleted, { x: 5, b: 15, d: 30 }); // d was edited after its deletion → kept
});

test('mergeData: a fresh device adopts the account data on ties', () => {
  const remote = { ...base(), settings: { budgets: { month: 5000 } }, categories: [{ id: 'fuel' }, { id: 'other' }] };
  const fresh = base();
  const m = L.mergeData(fresh, remote, 1);
  assert.equal(m.settings.budgets.month, 5000);
  assert.deepEqual(m.categories.map((c) => c.id), ['fuel', 'other']);
  assert.equal(L.canon({ a: 1, b: null, c: [1, { z: 1, y: 2 }] }), '{"a":1,"c":[1,{"y":2,"z":1}]}');
});

test('dayBalance: unspent and overspent days carry within the month, from CARRY_START', () => {
  const a = (date, cents) => ({ date, cents });
  // 10 € a day; 12-14 Oct: spent 8, 0, 13 → +2 +10 -3 = +9 by the 15th
  const allocs = [a('2026-10-12', 800), a('2026-10-14', 1300), a('2026-10-15', 500), a('2026-10-10', 9999)];
  assert.equal(L.dayBalance(1000, allocs, '2026-10-15', '2026-10-12'), 900);
  // Days before CARRY_START (11 Oct) never count, even if `since` is earlier
  assert.equal(L.dayBalance(1000, allocs, '2026-10-12', '2026-10-01'), 1000);
  // First day: nothing carried yet
  assert.equal(L.dayBalance(1000, allocs, '2026-10-12', '2026-10-12'), 0);
  // A new month starts from zero
  assert.equal(L.dayBalance(1000, [a('2026-11-01', 400)], '2026-11-02', '2026-10-12'), 600);
});

test('item history matches spellings and typos', () => {
  const ps = [
    { id: 'a', date: '2026-10-01', items: [{ name: 'Γάλα', cents: 150, cat: 'groceries', days: 1 }] },
    { id: 'b', date: '2026-10-02', items: [{ name: 'Γάλα', cents: 160, cat: 'groceries', days: 1 }, { name: 'Ψωμί', cents: 90, cat: 'groceries', days: 1 }] },
    { id: 'c', date: '2026-10-03', items: [{ name: 'γαλα', cents: 155, cat: 'groceries', days: 1 }, { name: 'Τυρί', cents: 400, cat: 'groceries', days: 1 }] },
    { id: 'd', date: '2026-10-04', items: [{ name: 'Μπανάνες', cents: 200, cat: 'groceries', days: 1 }, { name: 'Μπανανες ', cents: 210, cat: 'groceries', days: 1 }, { name: 'Μπαννάες', cents: 190, cat: 'groceries', days: 1 }] },
  ];
  assert.equal(L.itemKey('  Γάλα,  φρέσκο '), 'γαλα φρεσκο');
  assert.equal(L.itemKey('Χυμός'), L.itemKey('χυμοσ'));
  const known = L.knownItems(ps);
  const milk = known.find((k) => k.key === 'γαλα');
  assert.equal(milk.name, 'Γάλα');
  assert.equal(milk.count, 3);
  assert.equal(milk.cents, 155); // latest price

  assert.deepEqual(L.matchItem('ΓΑΛΑ', known), { item: milk, exact: true });
  assert.equal(L.matchItem('Γλάα', known).item.name, 'Γάλα'); // swapped letters
  assert.equal(L.matchItem('Γάλλα', known).item.name, 'Γάλα'); // extra letter
  assert.equal(L.matchItem('Γάλα', known).exact, true);
  assert.equal(L.matchItem('Τυρι', known).exact, true);
  assert.equal(L.matchItem('Τυρόπιτα', known), null);
  assert.equal(L.matchItem('Ρύζι', known), null);
  assert.equal(L.matchItem('Μπαμιές', known), null);
  assert.equal(L.matchItem('', known), null);

  assert.equal(L.typoDistance('abcd', 'abdc'), 1);
  assert.equal(L.typoDistance('kitten', 'sitting'), 3);

  const dups = L.duplicateItems(known);
  assert.deepEqual(dups.map((g) => g.name), ['Γάλα', 'Μπανάνες']);
  assert.deepEqual(dups[1].names.sort(), ['Μπανανες ', 'Μπαννάες'].sort());

  const copy = structuredClone(ps);
  assert.equal(L.renameItems(copy, dups[1].names, 'Μπανάνες'), 2);
  assert.deepEqual(copy[3].items.map((i) => i.name), ['Μπανάνες', 'Μπανάνες', 'Μπανάνες']);
});

test('categories with their own fund stay out of the general budgets', () => {
  const cats = [{ id: 'groceries', ownFund: true }, { id: 'coffee' }];
  const allocs = L.allocations([{ id: 'p', date: '2026-10-15', items: [
    { name: 'Σούπερ μάρκετ', cents: 7000, cat: 'groceries', days: 1 },
    { name: 'Καφές', cents: 300, cat: 'coffee', days: 1 },
  ] }]);
  const general = L.general(allocs, cats);
  assert.equal(L.sum(general), 300);
  assert.equal(L.dayBalance(1000, general, '2026-10-16'), 1000 * 5 - 300); // 11–15 Oct
  assert.equal(L.categoryBudgets([{ ...cats[0], budget: 6000, budgetPeriod: 'week' }], allocs, '2026-10-15')[0].spent, 7000);
  assert.equal(L.general(allocs, [{ id: 'groceries' }]).length, 2);
});

test('general payments stay out of the daily limit but count in the month', () => {
  const cats = [{ id: 'subs', offDaily: true }, { id: 'coffee' }, { id: 'other' }];
  const allocs = L.allocations([
    { id: 'a', date: '2026-10-15', items: [{ name: 'Netflix', cents: 1200, cat: 'subs', days: 1 }] },
    { id: 'b', date: '2026-10-15', items: [{ name: 'Καφές', cents: 300, cat: 'coffee', days: 1 }] },
    { id: 'c', date: '2026-10-16', offDaily: true, items: [{ name: 'Ασφάλεια', cents: 5000, cat: 'other', days: 1 }] },
  ]);
  const daily = L.daily(allocs, cats);
  assert.deepEqual(daily.map((a) => a.pid), ['b']);
  assert.equal(L.dayBalance(1000, daily, '2026-10-16'), 1000 * 5 - 300); // 11–15 Oct
  // Month budget 31 €: 15,00 € before today, 50 € paid today outside the daily limit, 16 days left.
  assert.equal(L.dailyAllowance(31000, allocs, 'month', '2026-10-16', 1, 5000), Math.floor((31000 - 1500 - 5000) / 16));
  assert.equal(L.daily(allocs, [{ id: 'subs' }]).length, 2);
});
