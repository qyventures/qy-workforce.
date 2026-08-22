import test from 'node:test';
import assert from 'node:assert/strict';
import { isValidOtp, isValidPhone, normalizeOtp, normalizePhone } from './otp.mjs';

test('normalizes common phone formatting without changing country code', () => {
  assert.equal(normalizePhone('+65 8123 4567'), '+6581234567');
  assert.equal(normalizePhone('+1 (415) 555-2671'), '+14155552671');
});

test('accepts only E.164-like phone numbers', () => {
  assert.equal(isValidPhone('+6581234567'), true);
  assert.equal(isValidPhone('+1 (415) 555-2671'), true);
  assert.equal(isValidPhone('81234567'), false);
  assert.equal(isValidPhone('+012345678'), false);
  assert.equal(isValidPhone('+65abc1234'), false);
});

test('normalizes OTP input to digits and caps length', () => {
  assert.equal(normalizeOtp('12 34-56'), '123456');
  assert.equal(normalizeOtp('1234567890'), '12345678');
});

test('requires a 4 to 8 digit OTP after normalization', () => {
  assert.equal(isValidOtp('1234'), true);
  assert.equal(isValidOtp('12345678'), true);
  assert.equal(isValidOtp('12 34 56'), true);
  assert.equal(isValidOtp('123'), false);
  assert.equal(isValidOtp('abcdefgh'), false);
});
