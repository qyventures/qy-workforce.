export const MAX_NAME_LENGTH: number;
export const MAX_EMAIL_LENGTH: number;
export const MAX_INTERESTS: number;
export function normalizeEmail(value: unknown): string;
export function isValidOptionalEmail(value: unknown): boolean;
export function canSubmitOnboarding(input: {
  fullName: unknown;
  email: unknown;
  selectedInterests: unknown;
  consented: boolean;
  submitting: boolean;
}): boolean;
