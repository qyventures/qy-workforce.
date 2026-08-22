export function isLikelyNetworkError(error: unknown): boolean {
  if (!error) return false;
  const message = typeof error === 'string'
    ? error
    : error instanceof Error
      ? error.message
      : typeof error === 'object' && 'message' in error
        ? String((error as { message?: unknown }).message ?? '')
        : '';

  const normalized = message.toLowerCase();
  return [
    'network request failed',
    'failed to fetch',
    'fetch failed',
    'networkerror',
    'timeout',
    'timed out',
    'connection',
    'offline',
  ].some((needle) => normalized.includes(needle));
}

export function mobileErrorMessage(
  error: unknown,
  fallback = 'Something went wrong. Please try again.',
): string {
  if (isLikelyNetworkError(error)) {
    return 'You may be offline or on an unstable connection. Reconnect and try again.';
  }

  if (error && typeof error === 'object' && 'message' in error) {
    const message = String((error as { message?: unknown }).message ?? '').trim();
    if (message) return message;
  }

  if (error instanceof Error && error.message.trim()) return error.message.trim();
  if (typeof error === 'string' && error.trim()) return error.trim();
  return fallback;
}
