import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_INTERESTS,
  canSubmitOnboarding,
  isValidDisplayName,
  isValidOptionalEmail,
  normalizeDisplayName,
  normalizeEmail,
} from './onboarding.mjs';

test('normalizes display names safely', () => {
  assert.equal(normalizeDisplayName('  Alex   Worker  '), 'Alex Worker');
  assert.equal(normalizeDisplayName('Alex\nWorker\u0000'), 'AlexWorker');
  assert.equal(normalizeDisplayName(null), '');
  assert.equal(isValidDisplayName('Alex Worker'), true);
  assert.equal(isValidDisplayName(' A '), false);
});

test('normalizes optional email safely', () => {
  assert.equal(normalizeEmail('  Worker@Example.COM '), 'worker@example.com');
  assert.equal(normalizeEmail(null), '');
});

test('accepts blank optional email and rejects malformed values', () => {
  assert.equal(isValidOptionalEmail(''), true);
  assert.equal(isValidOptionalEmail('worker@example.com'), true);
  assert.equal(isValidOptionalEmail('worker example.com'), false);
  assert.equal(isValidOptionalEmail('worker@'), false);
});

test('requires valid name, interests, consent and idle submit state', () => {
  const base = {
    fullName: 'Alex Worker',
    email: '',
    selectedInterests: ['retail'],
    consented: true,
    submitting: false,
  };

  assert.equal(canSubmitOnboarding(base), true);
  assert.equal(canSubmitOnboarding({ ...base, fullName: 'A' }), false);
  assert.equal(canSubmitOnboarding({ ...base, selectedInterests: [] }), false);
  assert.equal(canSubmitOnboarding({ ...base, consented: false }), false);
  assert.equal(canSubmitOnboarding({ ...base, submitting: true }), false);
  assert.equal(canSubmitOnboarding({ ...base, email: 'bad-email' }), false);
});

test('rejects interest selections above the mobile cap', () => {
  const selectedInterests = Array.from({ length: MAX_INTERESTS + 1 }, (_, index) => `role-${index}`);
  assert.equal(canSubmitOnboarding({
    fullName: 'Alex Worker',
    email: '',
    selectedInterests,
    consented: true,
    submitting: false,
  }), false);
});
