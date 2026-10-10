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
