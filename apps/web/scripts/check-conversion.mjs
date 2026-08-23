import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = join(here, '..', 'app');

const [employer, worker, api] = await Promise.all([
  readFile(join(appRoot, 'employers', 'page.tsx'), 'utf8'),
  readFile(join(appRoot, 'workers', 'page.tsx'), 'utf8'),
  readFile(join(appRoot, 'api', 'leads', 'route.ts'), 'utf8'),
]);

const failures = [];

function requireText(source, needle, label) {
  if (!source.includes(needle)) failures.push(label);
}

for (const [label, source, type] of [
  ['employer', employer, 'employer'],
  ['worker', worker, 'worker'],
]) {
  requireText(source, `type: '${type}'`, `${label} form must send the correct lead type`);
  requireText(source, "fetch('/api/leads'", `${label} form must submit only to /api/leads`);
  requireText(source, "consent: form.get('consent') === 'on'", `${label} form must send explicit consent state`);
  requireText(source, 'required type="checkbox" name="consent"', `${label} form must require consent before submission`);
  requireText(source, 'href="/privacy"', `${label} consent copy must link to the Privacy Notice`);
  requireText(source, 'name="website"', `${label} form must preserve the anti-bot honeypot field`);
  requireText(source, "'content-type':'application/json'", `${label} form must use the JSON lead contract`);
}

requireText(api, "type LeadType = 'employer' | 'worker'", 'lead endpoint must keep employer/worker type allow-listing');
requireText(api, 'const consent = body.consent === true;', 'lead endpoint must enforce explicit consent');
requireText(api, "if (text(body.website, 200)) return jsonResponse({ ok: true });", 'lead endpoint must preserve honeypot handling');
requireText(api, "const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;", 'lead endpoint must keep privileged Supabase access server-side');
requireText(api, "'Cache-Control': 'no-store, max-age=0'", 'lead responses must remain non-cacheable');
requireText(api, 'MAX_REQUEST_BYTES', 'lead endpoint must retain request-size limits');
requireText(api, "contentType.toLowerCase().startsWith('application/json')", 'lead endpoint must accept JSON only');
requireText(api, "request.headers.get('origin')", 'lead endpoint must retain same-origin browser checks');

if (employer.includes('SUPABASE_SERVICE_ROLE_KEY') || worker.includes('SUPABASE_SERVICE_ROLE_KEY')) {
  failures.push('privileged Supabase credentials must never appear in client-side conversion pages');
}

if (failures.length) {
  console.error('Conversion contract checks failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log('Conversion contract checks passed.');
