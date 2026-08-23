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

const industrySlugs = ['hospitality', 'food-beverage', 'cleaning', 'retail', 'promotions', 'events'];
const industryData = fs.readFileSync(path.join(root, 'app/industries/industry-data.ts'), 'utf8');
for (const slug of industrySlugs) {
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

const homePage = fs.readFileSync(path.join(root, 'app/page.tsx'), 'utf8');
if (!homePage.includes('href={`/industries/${id}`}')) {
  console.error('Homepage industry route regression: industry cards must link to dedicated landing pages.');
  process.exit(1);
}
if (homePage.includes('href={`/industries#${id}`}')) {
  console.error('Homepage industry route regression: legacy anchor links must not replace dedicated industry landing pages.');
  process.exit(1);
}

const requiredPrimaryNavigation = [
  'aria-label="Primary"',
  'aria-label="QY Workforce home"',
  'href="/industries"',
  'href="/how-it-works"',
  'href="/trust"',
  'href="/workers"',
  'href="/employers"',
  'data-analytics-event="nav_worker_journey"',
  'data-analytics-event="nav_employer_journey"',
];
const missingPrimaryNavigation = requiredPrimaryNavigation.filter((snippet) => !homePage.includes(snippet));
if (missingPrimaryNavigation.length) {
  console.error(`Public navigation regression: missing ${missingPrimaryNavigation.join(', ')}`);
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

console.log('Required public routes, primary navigation, industry routes, homepage landing links, Ops routes, Ops navigation and landmark checks passed.');