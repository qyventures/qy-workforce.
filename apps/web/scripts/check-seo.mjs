import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd());
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

const rootLayout = read('app/layout.tsx');
const employerLayout = read('app/employers/layout.tsx');
const workerLayout = read('app/workers/layout.tsx');
const sitemap = read('app/sitemap.ts');
const robots = read('app/robots.ts');

const failures = [];

if (!rootLayout.includes('metadataBase:') || !rootLayout.includes('https://workforce.qyvent.com')) {
  failures.push('Root metadata must define metadataBase with the HTTPS workforce.qyvent.com fallback.');
}
if (!rootLayout.includes('openGraph:') || !rootLayout.includes("robots: { index: true, follow: true }")) {
  failures.push('Root metadata must retain Open Graph metadata and public indexing directives.');
}

for (const [name, source] of [['employers', employerLayout], ['workers', workerLayout]]) {
  if (!source.includes('alternates:') || !source.includes('canonical:')) {
    failures.push(`${name} conversion route must retain canonical metadata.`);
  }
  if (!source.includes('openGraph:')) {
    failures.push(`${name} conversion route must retain Open Graph metadata.`);
  }
}

const requiredPublicPaths = ['/', '/employers', '/workers', '/how-it-works', '/industries', '/trust', '/privacy', '/terms'];
for (const publicPath of requiredPublicPaths) {
  if (!sitemap.includes(`'${publicPath}'`)) {
    failures.push(`Sitemap regression: missing ${publicPath}.`);
  }
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

console.log('SEO metadata, sitemap and robots regression checks passed.');
