const ALLOWED_PATHS = new Set([
  '/',
  '/onboarding',
  '/readiness',
  '/shifts',
  '/my-shifts',
  '/earnings',
]);

const ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function resolveAppRoute(rawUrl) {
  if (typeof rawUrl !== 'string' || rawUrl.length === 0 || rawUrl.length > 2048) return null;

  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  if (url.protocol !== 'qyworkforce:') return null;

  const host = url.hostname ? `/${url.hostname}` : '';
  const pathname = `${host}${url.pathname}`.replace(/\/{2,}/g, '/').replace(/\/$/, '') || '/';

  if (ALLOWED_PATHS.has(pathname)) return pathname;

  if (pathname === '/assignment' || pathname === '/attendance') {
    const assignmentId = url.searchParams.get('assignmentId');
    if (!assignmentId || !ID_PATTERN.test(assignmentId)) return null;
    return `${pathname}?assignmentId=${encodeURIComponent(assignmentId)}`;
  }

  return null;
}
