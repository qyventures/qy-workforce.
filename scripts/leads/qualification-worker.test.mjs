import test from 'node:test';
import assert from 'node:assert/strict';
import { buildOpeningMessage, createQualificationWorker, normalizeLead } from './qualification-worker.mjs';

const lead = {
  id: 'l1', name: 'Jane', phone: '+6591112222', whatsapp_consent_at: '2026-08-26T00:00:00Z',
  deployment_timeline: 'Next week', roles_headcount: '20 banquet staff', location: 'Orchard', requirements: 'Black attire',
};

test('normalises employer lead fields', () => {
  const n = normalizeLead('employer', lead);
  assert.equal(n.timeline, 'Next week');
  assert.equal(n.location, 'Orchard');
  assert.equal(n.lead_type, 'employer');
});

test('opening message requires consent and does not promise fulfilment', () => {
  const n = normalizeLead('employer', lead);
  const msg = buildOpeningMessage(n);
  assert.match(msg, /roles\/headcount/i);
  assert.doesNotMatch(msg, /guarantee/i);
  assert.throws(() => buildOpeningMessage({ ...n, whatsapp_consent_at: null }), /consent/i);
});

test('withdraws consent on STOP without another send', async () => {
  const calls = [];
  const repo = {
    getLead: async () => lead,
    addMessage: async x => calls.push(['message', x]),
    withdrawWhatsappConsent: async () => calls.push(['withdraw']),
    cancelQueueForLead: async () => calls.push(['cancel']),
  };
  const worker = createQualificationWorker({
    repository: repo,
    messenger: { send: async () => { throw new Error('should not send'); } },
    qualifier: { qualify: async () => ({}) },
    sheetClient: {},
  });
  const result = await worker.handleInbound({ leadType: 'employer', leadId: 'l1', text: 'STOP' });
  assert.equal(result.status, 'stopped');
  assert.deepEqual(calls.map(x => x[0]), ['message', 'withdraw', 'cancel']);
});

test('completed qualification hands off to sheet without sending another message', async () => {
  const calls = [];
  const repo = {
    getLead: async () => lead,
    addMessage: async () => {},
    getConversation: async () => [],
    updateLead: async (...x) => calls.push(['lead', x]),
    markQueueForLead: async (...x) => calls.push(['queue', x]),
  };
  const worker = createQualificationWorker({
    repository: repo,
    messenger: { send: async () => { throw new Error('should not send'); } },
    qualifier: { qualify: async () => ({ complete: true, summary: '20 staff next week in Orchard', score: 88 }) },
    sheetClient: { upsertQualifiedLead: async x => calls.push(['sheet', x]) },
  });
  const result = await worker.handleInbound({ leadType: 'employer', leadId: 'l1', text: 'Need 20 next week' });
  assert.equal(result.status, 'handoff_ready');
  assert.equal(result.score, 88);
  assert.equal(calls.some(x => x[0] === 'sheet'), true);
});
