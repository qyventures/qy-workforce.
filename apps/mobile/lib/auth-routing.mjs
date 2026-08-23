export function resolveAuthRedirect({ configured, sessionResolved, authenticated, segment }) {
  if (!configured || !sessionResolved) return null;

  const onSignIn = segment === 'sign-in';
  if (!authenticated && !onSignIn) return '/sign-in';
  if (authenticated && onSignIn) return '/';
  return null;
}

export function canOpenTrustedRoute({ configured, sessionResolved, authenticated }) {
  if (!sessionResolved) return false;
  if (!configured) return true;
  return authenticated;
}
