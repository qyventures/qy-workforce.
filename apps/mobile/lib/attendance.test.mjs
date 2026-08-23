import test from 'node:test';
import assert from 'node:assert/strict';
import { attendanceActionLabel, attendanceRouteMode, attendanceState, clockErrorMessage, formatAttendanceSchedule, formatAttendanceTimestamp, formatRecordedPay, nextClockAction } from './attendance.mjs';

test('attendance route fails closed when backend is configured and assignment is missing', () => {
  assert.equal(attendanceRouteMode(false, undefined), 'demo');
  assert.equal(attendanceRouteMode(true, 'demo-assignment'), 'demo');
  assert.equal(attendanceRouteMode(true, undefined), 'invalid');
  assert.equal(attendanceRouteMode(true, ''), 'invalid');
  assert.equal(attendanceRouteMode(true, '  '), 'invalid');
  assert.equal(attendanceRouteMode(true, 'a-real-assignment-id'), 'live');
});

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

test('attendance schedule fails safely on malformed or reversed timestamps', () => {
  assert.equal(formatAttendanceSchedule('', '2026-08-23T09:00:00Z'), 'Schedule unavailable');
  assert.equal(formatAttendanceSchedule('not-a-date', '2026-08-23T09:00:00Z'), 'Schedule unavailable');
  assert.equal(formatAttendanceSchedule('2026-08-23T09:00:00Z', '2026-08-23T08:00:00Z'), 'Schedule unavailable');
  assert.notEqual(formatAttendanceSchedule('2026-08-23T01:00:00Z', '2026-08-23T09:00:00Z'), 'Schedule unavailable');
});

test('attendance timestamps never render Invalid Date', () => {
  assert.equal(formatAttendanceTimestamp(null), 'Time unavailable');
  assert.equal(formatAttendanceTimestamp('bad-value'), 'Time unavailable');
  assert.equal(formatAttendanceTimestamp('bad-value', 'Not recorded'), 'Not recorded');
  assert.doesNotMatch(formatAttendanceTimestamp('2026-08-23T01:00:00Z'), /invalid date/i);
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
