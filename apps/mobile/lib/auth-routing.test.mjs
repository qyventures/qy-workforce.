import test from 'node:test';
import assert from 'node:assert/strict';
import { canOpenTrustedRoute, resolveAuthRedirect } from './auth-routing.mjs';

test('does not redirect while auth is unresolved', () => {
  assert.equal(resolveAuthRedirect({ configured: true, sessionResolved: false, authenticated: false, segment: 'shifts' }), null);
});

test('keeps demo mode navigable when staging auth is not configured', () => {
  assert.equal(resolveAuthRedirect({ configured: false, sessionResolved: true, authenticated: false, segment: 'shifts' }), null);
});

test('redirects unauthenticated users away from protected worker routes', () => {
  assert.equal(resolveAuthRedirect({ configured: true, sessionResolved: true, authenticated: false, segment: 'attendance' }), '/sign-in');
});

test('allows unauthenticated users to remain on sign in', () => {
  assert.equal(resolveAuthRedirect({ configured: true, sessionResolved: true, authenticated: false, segment: 'sign-in' }), null);
});

test('redirects authenticated users away from sign in', () => {
  assert.equal(resolveAuthRedirect({ configured: true, sessionResolved: true, authenticated: true, segment: 'sign-in' }), '/');
});

test('defers trusted notification routes until auth resolves', () => {
  assert.equal(canOpenTrustedRoute({ configured: true, sessionResolved: false, authenticated: false }), false);
  assert.equal(canOpenTrustedRoute({ configured: true, sessionResolved: true, authenticated: false }), false);
  assert.equal(canOpenTrustedRoute({ configured: true, sessionResolved: true, authenticated: true }), true);
});

test('allows trusted routes in non-production demo mode after initial resolution', () => {
  assert.equal(canOpenTrustedRoute({ configured: false, sessionResolved: true, authenticated: false }), true);
});
