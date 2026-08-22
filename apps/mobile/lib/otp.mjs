export const MAX_OTP_LENGTH = 8;

export function normalizePhone(value) {
  return String(value ?? '').replace(/[\s()-]/g, '');
}

export function isValidPhone(value) {
  return /^\+[1-9]\d{7,14}$/.test(normalizePhone(value));
}

export function normalizeOtp(value) {
  return String(value ?? '').replace(/\D/g, '').slice(0, MAX_OTP_LENGTH);
}

export function isValidOtp(value) {
  return /^\d{4,8}$/.test(normalizeOtp(value));
}
