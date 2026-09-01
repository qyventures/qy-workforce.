import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const route = readFileSync(new URL('../../apps/web/app/api/leads/route.ts', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../../supabase/migrations/202609020545_lead_whatsapp_sender_alignment.sql', import.meta.url), 'utf8');

assert.match(route, /sender:\s*'\+6580227816'/);
assert.doesNotMatch(route, /sender:\s*'\+6584317050'/);
assert.match(migration, /alter column sender set default '\+6580227816'/i);
assert.doesNotMatch(migration, /set default '\+6584317050'/i);

console.log('WhatsApp sender alignment checks passed');
