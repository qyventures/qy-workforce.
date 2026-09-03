export const MAX_REPORT_DAYS = 366;

export function isAuthorisationError(error: { message?: string } | null | undefined) {
  const message = error?.message?.toLowerCase() ?? '';
  return message.includes('jwt') || message.includes('authentication') || message.includes('authoris') || message.includes('permission denied');
}

/** Keep database/RPC details out of the Ops UI while preserving a useful sign-in hint. */
export function safeOpsError(error: { message?: string } | null | undefined, fallback: string) {
  return isAuthorisationError(error)
    ? 'Sign in with an authorised Ops, supervisor, finance or admin account to continue.'
    : fallback;
}

export function validateDateRange(start: string, end: string) {
  if (!start || !end || end < start) return 'Choose a valid period with the end date on or after the start date.';
  const startDate = new Date(`${start}T00:00:00Z`);
  const endDate = new Date(`${end}T00:00:00Z`);
  const days = (endDate.getTime() - startDate.getTime()) / 86_400_000 + 1;
  return Number.isFinite(days) && days <= MAX_REPORT_DAYS
    ? null
    : `Choose a reporting period of ${MAX_REPORT_DAYS} days or fewer.`;
}
