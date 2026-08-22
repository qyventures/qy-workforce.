import test from 'node:test';
import assert from 'node:assert/strict';
import { attendanceActionLabel, attendanceState, clockErrorMessage, formatRecordedPay, nextClockAction } from './attendance.mjs';

test('attendance state follows server timestamps', () => {
  assert.equal(attendanceState(null), 'idle');
  assert.equal(attendanceState({ clock_in_at: null, clock_out_at: null }), 'idle');
  assert.equal(attendanceState({ clock_in_at: '2026-08-23T01:00:00Z', clock_out_at: null }), 'clocked-in');
  assert.equal(attendanceState({ clock_in_at: '2026-08-23T01:00:00Z', clock_out_at: '2026-08-23T09:00:00Z' }), 'clocked-out');
});

test('next action never allows another event after clock out', () => {
  assert.equal(nextClockAction({ clock_in_at: null, clock_out_at: null }), 'in');
  assert.equal(nextClockAction({ clock_in_at: 'x', clock_out_at: null }), 'out');
  assert.equal(nextClockAction({ clock_in_at: 'x', clock_out_at: 'y' }), null);
  assert.equal(attendanceActionLabel({ clock_in_at: 'x', clock_out_at: 'y' }), 'Shift completed');
});

test('timesheet summary safely normalizes malformed values', () => {
  assert.equal(formatRecordedPay(null), 'A draft timesheet is being prepared.');
  assert.equal(formatRecordedPay({ payable_minutes: 95, worker_amount: 24.5, status: 'draft' }), '1h 35m recorded · Est. S$24.50 · draft');
  assert.equal(formatRecordedPay({ payable_minutes: -10, worker_amount: Number.NaN, status: '' }), '0h 0m recorded · Est. S$0.00 · pending');
});

test('known server geofence errors map to safe worker guidance', () => {
  assert.match(clockErrorMessage('outside approved worksite geofence'), /outside the approved worksite area/i);
  assert.match(clockErrorMessage('location accuracy insufficient'), /not accurate enough/i);
  assert.equal(clockErrorMessage('permission denied'), null);
});
