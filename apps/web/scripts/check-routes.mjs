import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd());

const requiredPages = [
  'app/page.tsx',
  'app/employers/page.tsx',
  'app/workers/page.tsx',
  'app/industries/page.tsx',
  'app/how-it-works/page.tsx',
  'app/trust/page.tsx',
  'app/privacy/page.tsx',
  'app/terms/page.tsx',
  'app/ops/page.tsx',
  'app/ops/workers/page.tsx',
  'app/ops/exceptions/page.tsx',
  'app/ops/approvals/page.tsx',
  'app/ops/timesheets/page.tsx',
  'app/ops/clients/page.tsx',
  'app/ops/shifts/page.tsx',
  'app/ops/shifts/new/page.tsx',
  'app/ops/reports/page.tsx',
];

const missingPages = requiredPages.filter((relativePath) => !fs.existsSync(path.join(root, relativePath)));
if (missingPages.length) {
  console.error(`Required route regression: missing ${missingPages.join(', ')}`);
  process.exit(1);
}

const opsLayout = fs.readFileSync(path.join(root, 'app/ops/layout.tsx'), 'utf8');
const requiredOpsLinks = [
  '/ops/shifts',
  '/ops/workers',
  '/ops/clients',
  '/ops/exceptions',
  '/ops/approvals',
  '/ops/timesheets',
  '/ops/reports',
];

const missingOpsLinks = requiredOpsLinks.filter((href) => !opsLayout.includes(`href: '${href}'`));
if (missingOpsLinks.length) {
  console.error(`Ops navigation regression: missing ${missingOpsLinks.join(', ')}`);
  process.exit(1);
}

const dashboard = fs.readFileSync(path.join(root, 'app/ops/page.tsx'), 'utf8');
if ((dashboard.match(/<main\b/g) ?? []).length > 0) {
  console.error('Ops dashboard regression: page must not nest a second <main> inside the protected Ops layout.');
  process.exit(1);
}

console.log('Required public routes, Ops routes and Ops navigation checks passed.');
