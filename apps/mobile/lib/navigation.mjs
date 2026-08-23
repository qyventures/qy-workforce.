const ALLOWED_PATHS = new Set([
  '/',
  '/readiness',
  '/shifts',
  '/my-shifts',
  '/earnings',
  '/notifications',
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
  if (url.username || url.password || url.hash) return null;

  const host = url.hostname ? `/${url.hostname}` : '';
  const pathname = `${host}${url.pathname}`.replace(/\/{2,}/g, '/').replace(/\/$/, '') || '/';

  if (ALLOWED_PATHS.has(pathname)) {
    return url.searchParams.size === 0 ? pathname : null;
  }

  if (pathname === '/assignment' || pathname === '/attendance') {
    const keys = [...url.searchParams.keys()];
    const assignmentIds = url.searchParams.getAll('assignmentId');
    if (keys.length !== 1 || keys[0] !== 'assignmentId' || assignmentIds.length !== 1) return null;

    const assignmentId = assignmentIds[0];
    if (!ID_PATTERN.test(assignmentId)) return null;
    return `${pathname}?assignmentId=${encodeURIComponent(assignmentId)}`;
  }

  return null;
}
