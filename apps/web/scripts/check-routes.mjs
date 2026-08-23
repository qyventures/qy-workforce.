import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd());

const requiredPages = [
  'app/page.tsx',
  'app/employers/page.tsx',
  'app/workers/page.tsx',
  'app/industries/page.tsx',
  'app/industries/[slug]/page.tsx',
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

const industryData = fs.readFileSync(path.join(root, 'app/industries/industry-data.ts'), 'utf8');
for (const slug of ['hospitality', 'food-beverage', 'cleaning', 'retail', 'promotions', 'events']) {
  if (!industryData.includes(`id: '${slug}'`)) {
    console.error(`Industry route regression: missing configured industry ${slug}`);
    process.exit(1);
  }
}

const industryPage = fs.readFileSync(path.join(root, 'app/industries/[slug]/page.tsx'), 'utf8');
if (!industryPage.includes('generateStaticParams') || !industryPage.includes('notFound()')) {
  console.error('Industry route regression: dynamic industry pages must define static params and reject unknown slugs.');
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

function walkPages(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return walkPages(fullPath);
    return entry.isFile() && entry.name === 'page.tsx' ? [fullPath] : [];
  });
}

const opsPages = walkPages(path.join(root, 'app/ops'));
const pagesWithNestedMain = opsPages
  .filter((filePath) => /<main\b/.test(fs.readFileSync(filePath, 'utf8')))
  .map((filePath) => path.relative(root, filePath));

if (pagesWithNestedMain.length) {
  console.error(`Ops landmark regression: protected Ops pages must rely on app/ops/layout.tsx for the single <main>: ${pagesWithNestedMain.join(', ')}`);
  process.exit(1);
}

console.log('Required public routes, industry routes, Ops routes, Ops navigation and landmark checks passed.');
