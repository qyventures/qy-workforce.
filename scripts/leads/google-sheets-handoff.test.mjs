import test from 'node:test';
import assert from 'node:assert/strict';
import { findExistingLeadRow, handoffToRow, normalizeEmail, normalizePhone } from './google-sheets-handoff.mjs';

const lead = {
  created_at: '2026-08-26T00:00:00.000Z',
  lead_type: 'employer',
  source: 'website_employer',
  campaign: 'meta_employer_flexible_worker_preview',
  name: 'Jane Tan',
  company: 'Example Pte Ltd',
  phone: '+65 8431 7050',
  email: 'Jane@Example.com',
  whatsapp_consent_at: '2026-08-26T00:00:00.000Z',
  timeline: 'Next week',
  roles: 'Banquet staff',
  headcount: '20',
  location: 'Orchard',
  schedule: '18:00-23:00',
  budget_or_pay: '',
  requirements: '=HYPERLINK("https://bad.example")',
  notes: '@formula-looking note',
};

test('normalizes phone and email for deterministic dedupe', () => {
  assert.equal(normalizePhone('+65 8431-7050'), '6584317050');
  assert.equal(normalizeEmail(' Jane@Example.COM '), 'jane@example.com');
});

test('finds an existing row by normalized phone or email', () => {
  const rows = [
    ['Created At', 'Lead Type', 'Source', 'Campaign', 'Name', 'Company', 'Contact Number', 'Email'],
    ['', '', '', '', 'Existing', '', '+65 9000 0000', 'first@example.com'],
    ['', '', '', '', 'Jane', '', '6584317050', 'jane@example.com'],
  ];
  assert.equal(findExistingLeadRow(rows, { phone: '+65 8431 7050', email: 'new@example.com' }), 3);
  assert.equal(findExistingLeadRow(rows, { phone: '+65 8111 1111', email: 'FIRST@EXAMPLE.COM' }), 2);
  assert.equal(findExistingLeadRow(rows, { phone: '+65 8222 2222', email: 'none@example.com' }), null);
});

test('maps a qualified lead to 26 columns and neutralises formula injection', () => {
  const row = handoffToRow({ lead, summary: 'Clear deployment need', score: 85, status: 'handoff_ready', conversationId: 'conv-1' });
  assert.equal(row.length, 26);
  assert.equal(row[6], '+65 8431 7050');
  assert.equal(row[7], 'Jane@Example.com');
  assert.equal(row[8], 'Yes');
  assert.equal(row[15], "'=HYPERLINK(\"https://bad.example\")");
  assert.equal(row[25], "'@formula-looking note");
});
