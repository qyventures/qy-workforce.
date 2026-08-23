import test from 'node:test';
import assert from 'node:assert/strict';
import { HOME_ACTIONS, homeAction } from './home-actions.mjs';

test('clock in action routes through accepted shifts instead of unscoped attendance', () => {
  const action = homeAction('Clock in / out');
  assert.ok(action);
  assert.equal(action.href, '/my-shifts');
  assert.match(action.body, /accepted shift/i);
});

test('home actions never expose an unscoped attendance route', () => {
  assert.equal(HOME_ACTIONS.some(action => action.href === '/attendance'), false);
});
