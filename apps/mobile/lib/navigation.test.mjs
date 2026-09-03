import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveAppRoute } from './navigation.mjs';

const assignmentId = '123e4567-e89b-42d3-a456-426614174000';

test('allows known worker routes', () => {
  assert.equal(resolveAppRoute('qyworkforce://shifts'), '/shifts');
  assert.equal(resolveAppRoute('qyworkforce://earnings'), '/earnings');
});

test('allows assignment routes only with a valid assignment id', () => {
  assert.equal(
    resolveAppRoute(`qyworkforce://assignment?assignmentId=${assignmentId}`),
    `/assignment?assignmentId=${assignmentId}`,
  );
  assert.equal(resolveAppRoute('qyworkforce://assignment?assignmentId=bad'), null);
  assert.equal(resolveAppRoute('qyworkforce://assignment'), null);
});

test('allows attendance routes only with a valid assignment id', () => {
  assert.equal(
    resolveAppRoute(`qyworkforce://attendance?assignmentId=${assignmentId}`),
    `/attendance?assignmentId=${assignmentId}`,
  );
  assert.equal(resolveAppRoute('qyworkforce://attendance?assignmentId=bad'), null);
});

test('rejects untrusted schemes and unknown routes', () => {
  assert.equal(resolveAppRoute('https://example.com/shifts'), null);
  assert.equal(resolveAppRoute('javascript:alert(1)'), null);
  assert.equal(resolveAppRoute('qyworkforce://admin'), null);
});

test('rejects malformed and oversized input', () => {
  assert.equal(resolveAppRoute('not-a-url'), null);
  assert.equal(resolveAppRoute(`qyworkforce://shifts?x=${'a'.repeat(2100)}`), null);
});
