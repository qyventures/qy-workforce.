import test from 'node:test';
import assert from 'node:assert/strict';
import { formatShiftTime, normalizeAvailableShift, parseRequirements, shiftAccessibilityLabel } from './shifts.mjs';

test('parseRequirements supports arrays and boolean maps', () => {
  assert.deepEqual(parseRequirements([' Black pants ', '', 7, 'Covered shoes']), ['Black pants', 'Covered shoes']);
  assert.deepEqual(parseRequirements({ black_pants: true, covered_shoes: 1, apron: false }), ['black pants', 'covered shoes']);
});

test('normalizeAvailableShift rejects rows without trusted identifiers or schedules', () => {
  assert.equal(normalizeAvailableShift(null), null);
  assert.equal(normalizeAvailableShift({ shift_id: '', starts_at: '2026-08-23', ends_at: '2026-08-23' }), null);
  assert.equal(normalizeAvailableShift({ shift_id: 'shift-1', starts_at: 'bad', ends_at: '2026-08-23' }), null);
});

test('normalizeAvailableShift sanitizes presentation fields without deciding eligibility', () => {
  const shift = normalizeAvailableShift({
    shift_id: 'shift-1', role_name: '', client_name: 'Hotel', site_name: 'Ballroom',
    starts_at: '2026-08-23T10:00:00+08:00', ends_at: '2026-08-23T14:00:00+08:00',
    worker_rate: '16.5', available_slots: '2.9', requirements: ['Covered shoes'],
  });
  assert.deepEqual(shift, {
    id: 'shift-1', role: 'Shift', client: 'Hotel', site: 'Ballroom',
    startsAt: '2026-08-23T10:00:00+08:00', endsAt: '2026-08-23T14:00:00+08:00',
    rate: 16.5, availableSlots: 2, requirements: ['Covered shoes'],
  });
});

test('formatShiftTime and accessibility label remain readable', () => {
  assert.equal(formatShiftTime('bad', 'also-bad'), 'Schedule unavailable');
  const shift = normalizeAvailableShift({
    shift_id: 'shift-2', role_name: 'Banquet Crew', client_name: 'Hotel', site_name: 'Ballroom',
    starts_at: '2026-08-23T17:00:00+08:00', ends_at: '2026-08-23T23:00:00+08:00',
    worker_rate: 16, available_slots: 1,
  });
  assert.ok(shift);
  const label = shiftAccessibilityLabel(shift);
  assert.match(label, /Banquet Crew/);
  assert.match(label, /S\$16\.00 per hour/);
  assert.match(label, /1 slot remaining/);
});
