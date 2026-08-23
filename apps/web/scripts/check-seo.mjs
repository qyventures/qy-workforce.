import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd());
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const rootLayout = read('app/layout.tsx');
const employerLayout = read('app/employers/layout.tsx');
const workerLayout = read('app/workers/layout.tsx');
const howItWorksLayout = read('app/how-it-works/layout.tsx');
const industriesLayout = read('app/industries/layout.tsx');
const industryPage = read('app/industries/[slug]/page.tsx');
const industryData = read('app/industries/industry-data.ts');
const trustLayout = read('app/trust/layout.tsx');
const privacyPage = read('app/privacy/page.tsx');
const termsPage = read('app/terms/page.tsx');
const sitemap = read('app/sitemap.ts');
const robots = read('app/robots.ts');

const failures = [];

if (!rootLayout.includes('metadataBase:') || !rootLayout.includes('https://workforce.qyvent.com')) {
  failures.push('Root metadata must define metadataBase with the HTTPS workforce.qyvent.com fallback.');
}
if (!rootLayout.includes('openGraph:') || !rootLayout.includes("robots: { index: true, follow: true }")) {
  failures.push('Root metadata must retain Open Graph metadata and public indexing directives.');
}

for (const [name, source] of [
  ['employers', employerLayout],
  ['workers', workerLayout],
  ['how-it-works', howItWorksLayout],
  ['industries', industriesLayout],
  ['trust', trustLayout],
  ['privacy', privacyPage],
  ['terms', termsPage],
]) {
  if (!source.includes('alternates:') || !source.includes('canonical:')) {
    failures.push(`${name} public route must retain canonical metadata.`);
  }
  if (!source.includes('openGraph:')) {
    failures.push(`${name} public route must retain Open Graph metadata.`);
  }
}

if (!industryPage.includes('generateMetadata') || !industryPage.includes('alternates: { canonical }') || !industryPage.includes('openGraph:')) {
  failures.push('Dynamic industry routes must retain generated canonical and Open Graph metadata.');
}
if (!industryPage.includes('generateStaticParams')) {
  failures.push('Dynamic industry routes must remain statically enumerable for crawlability.');
}
if (!industryPage.includes("'@type': 'Service'") || !industryPage.includes('application/ld+json') || !industryPage.includes("name: 'Singapore'")) {
  failures.push('Dynamic industry routes must retain Service JSON-LD with Singapore areaServed.');
}
if (!industryPage.includes("replace(/</g, '\\\\u003c')")) {
  failures.push('Industry JSON-LD must keep less-than escaping before injection.');
}
for (const slug of ['hospitality', 'food-beverage', 'cleaning', 'retail', 'promotions', 'events']) {
  if (!industryData.includes(`id: '${slug}'`)) failures.push(`Industry SEO regression: missing ${slug}.`);
}

const requiredPublicPaths = ['/', '/employers', '/workers', '/how-it-works', '/industries', '/trust', '/privacy', '/terms'];
for (const publicPath of requiredPublicPaths) {
  if (!sitemap.includes(`'${publicPath}'`)) {
    failures.push(`Sitemap regression: missing ${publicPath}.`);
  }
}
if (!sitemap.includes("industries.map((industry) => `/industries/${industry.id}`)")) {
  failures.push('Sitemap must include all configured industry landing pages.');
}
if (sitemap.includes("'/ops") || sitemap.includes("'/api")) {
  failures.push('Sitemap must not expose Ops or API routes.');
}

for (const privatePath of ['/ops/', '/api/']) {
  if (!robots.includes(`'${privatePath}'`)) {
    failures.push(`robots.ts must disallow ${privatePath}.`);
  }
}
if (!robots.includes('/sitemap.xml')) {
  failures.push('robots.ts must advertise sitemap.xml.');
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log('SEO metadata, structured data, industry landing pages, sitemap and robots regression checks passed.');
