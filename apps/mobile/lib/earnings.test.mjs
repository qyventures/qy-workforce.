import test from 'node:test';
import assert from 'node:assert/strict';
import { earningsBucket, formatMoney, payableDuration, sumEarnings } from './earnings.mjs';

test('formats worker earnings safely', () => {
  assert.equal(formatMoney(12.5), 'S$12.50');
  assert.equal(formatMoney(Number.NaN), 'S$0.00');
});

test('formats payable duration', () => {
  assert.equal(payableDuration(485), '8h 5m');
  assert.equal(payableDuration(-10), '0h 0m');
});

test('maps payroll statuses to worker-facing buckets', () => {
  assert.equal(earningsBucket('paid'), 'approved');
  assert.equal(earningsBucket('payroll_ready'), 'approved');
  assert.equal(earningsBucket('rejected'), 'rejected');
  assert.equal(earningsBucket('submitted'), 'pending');
});

test('sums approved and pending earnings without counting rejected rows', () => {
  const totals = sumEarnings([
    { timesheet: { status: 'approved', worker_amount: 100 } },
    { timesheet: { status: 'submitted', worker_amount: 25.5 } },
    { timesheet: { status: 'rejected', worker_amount: 50 } },
  ]);
  assert.deepEqual(totals, { approved: 100, pending: 25.5 });
});
