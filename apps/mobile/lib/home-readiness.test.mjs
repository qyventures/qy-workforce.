import test from 'node:test';
import assert from 'node:assert/strict';
import { homeReadinessPresentation } from './home-readiness.mjs';

test('falls back safely when readiness is unavailable', () => {
  assert.deepEqual(homeReadinessPresentation(null), {
    label: 'Check your verified status',
    detail: 'Open readiness to review your worker checks.',
    ready: false,
  });
});

test('presents deployable workers without recomputing eligibility', () => {
  assert.deepEqual(homeReadinessPresentation({ deployable: true, approved_roles: 2 }), {
    label: 'Ready for deployment',
    detail: '2 approved roles available for matching.',
    ready: true,
  });
});

test('surfaces outstanding training for non-deployable workers', () => {
  assert.deepEqual(homeReadinessPresentation({ deployable: false, outstanding_training: 1 }), {
    label: 'Readiness checks pending',
    detail: '1 training item still outstanding.',
    ready: false,
  });
});

test('normalizes malformed counts safely', () => {
  assert.deepEqual(homeReadinessPresentation({ deployable: true, approved_roles: -4 }), {
    label: 'Ready for deployment',
    detail: 'Your verified worker checks are complete.',
    ready: true,
  });
});
