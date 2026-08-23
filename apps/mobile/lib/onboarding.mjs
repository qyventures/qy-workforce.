export const MAX_NAME_LENGTH = 120;
export const MAX_EMAIL_LENGTH = 254;
export const MAX_INTERESTS = 5;

export function normalizeDisplayName(value) {
  return String(value ?? '')
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

export function isValidDisplayName(value) {
  const name = normalizeDisplayName(value);
  return name.length >= 2 && name.length <= MAX_NAME_LENGTH;
}

export function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

export function isValidOptionalEmail(value) {
  const email = normalizeEmail(value);
  if (!email) return true;
  if (email.length > MAX_EMAIL_LENGTH) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

export function canSubmitOnboarding({ fullName, email, selectedInterests, consented, submitting }) {
  const interests = Array.isArray(selectedInterests) ? selectedInterests : [];

  return isValidDisplayName(fullName)
    && isValidOptionalEmail(email)
    && interests.length > 0
    && interests.length <= MAX_INTERESTS
    && consented === true
    && submitting !== true;
}
