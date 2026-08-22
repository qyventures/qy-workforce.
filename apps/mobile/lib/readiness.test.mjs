import test from 'node:test';
import assert from 'node:assert/strict';
import { getReadinessChecks, normalizeWorkerStatus, readinessSummary } from './readiness.mjs';

test('normalizeWorkerStatus produces a safe worker-facing label', () => {
  assert.equal(normalizeWorkerStatus(' active '), 'ACTIVE');
  assert.equal(normalizeWorkerStatus(''), 'PENDING');
  assert.equal(normalizeWorkerStatus(null), 'PENDING');
});

test('readiness checks require positive verified values', () => {
  const checks = Object.fromEntries(getReadinessChecks({
    identity_verified: true,
    residency_verified: false,
    work_eligibility: 'eligible',
    approved_roles: 1,
    outstanding_training: 0,
    failed_vetting: 0,
    required_consents_complete: true,
  }));

  assert.equal(checks['Identity verified'], true);
  assert.equal(checks['Residency verified'], false);
  assert.equal(checks['Approved role'], true);
  assert.equal(checks['Required consent recorded'], true);
});

test('readiness summary prefers deployable state and counts checks', () => {
  const summary = readinessSummary({
    worker_status: 'pending',
    deployable: true,
    identity_verified: true,
    residency_verified: true,
    work_eligibility: 'eligible',
    approved_roles: 2,
    outstanding_training: 0,
    failed_vetting: 0,
    required_consents_complete: true,
  });

  assert.equal(summary.statusLabel, 'DEPLOYABLE');
  assert.equal(summary.readyCount, 7);
  assert.equal(summary.totalCount, 7);
});
