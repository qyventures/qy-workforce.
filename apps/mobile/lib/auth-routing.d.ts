export function resolveAuthRedirect(input: {
  configured: boolean;
  sessionResolved: boolean;
  authenticated: boolean;
  segment?: string;
}): '/' | '/sign-in' | null;

export function canOpenTrustedRoute(input: {
  configured: boolean;
  sessionResolved: boolean;
  authenticated: boolean;
}): boolean;
