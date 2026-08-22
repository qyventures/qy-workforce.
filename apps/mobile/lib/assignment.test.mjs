import test from 'node:test';
import assert from 'node:assert/strict';
import { estimatedScheduledPay, normalizeAssignmentSchedule, safeHourlyRate } from './assignment.mjs';

test('normalizes a valid assignment schedule', () => {
  const schedule = normalizeAssignmentSchedule('2026-08-23T01:00:00.000Z', '2026-08-23T09:30:00.000Z');
  assert.ok(schedule);
  assert.equal(schedule.durationMinutes, 510);
});

test('rejects malformed or non-positive assignment schedules', () => {
  assert.equal(normalizeAssignmentSchedule('bad', '2026-08-23T09:30:00.000Z'), null);
  assert.equal(normalizeAssignmentSchedule('2026-08-23T09:30:00.000Z', '2026-08-23T09:30:00.000Z'), null);
  assert.equal(normalizeAssignmentSchedule('2026-08-23T10:00:00.000Z', '2026-08-23T09:30:00.000Z'), null);
});

test('accepts only finite non-negative hourly rates', () => {
  assert.equal(safeHourlyRate(16), 16);
  assert.equal(safeHourlyRate('17.5'), 17.5);
  assert.equal(safeHourlyRate(-1), null);
  assert.equal(safeHourlyRate('nope'), null);
  assert.equal(safeHourlyRate(null), null);
});

test('calculates scheduled pay only for valid inputs', () => {
  assert.equal(estimatedScheduledPay(480, 16), 128);
  assert.equal(estimatedScheduledPay(-1, 16), null);
  assert.equal(estimatedScheduledPay(480, -2), null);
});
