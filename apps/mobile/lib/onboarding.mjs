export const MAX_NAME_LENGTH = 120;
export const MAX_EMAIL_LENGTH = 254;
export const MAX_INTERESTS = 5;

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
  const trimmedName = String(fullName ?? '').trim();
  const interests = Array.isArray(selectedInterests) ? selectedInterests : [];

  return trimmedName.length >= 2
    && trimmedName.length <= MAX_NAME_LENGTH
    && isValidOptionalEmail(email)
    && interests.length > 0
    && interests.length <= MAX_INTERESTS
    && consented === true
    && submitting !== true;
}
