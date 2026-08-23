import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd());

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

const rootLayout = read('app/layout.tsx');
if (!/<html\s+lang=["']en["']/.test(rootLayout)) {
  console.error('Accessibility regression: root layout must declare an English document language.');
  process.exit(1);
}

const opsLayout = read('app/ops/layout.tsx');
const opsRequirements = [
  ['skip link', /href=["']#ops-main["']/],
  ['labelled operations navigation', /<nav[^>]+aria-label=["']Operations["']/],
  ['single focusable main landmark', /<main[^>]+id=["']ops-main["'][^>]+tabIndex=\{-1\}/],
];

for (const [label, pattern] of opsRequirements) {
  if (!pattern.test(opsLayout)) {
    console.error(`Accessibility regression: Ops shell is missing ${label}.`);
    process.exit(1);
  }
}

function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return walk(fullPath);
    return entry.isFile() && /\.(tsx|jsx)$/.test(entry.name) ? [fullPath] : [];
  });
}

const appFiles = walk(path.join(root, 'app'));
const tableHeaderViolations = [];
const imageAltViolations = [];

for (const filePath of appFiles) {
  const source = fs.readFileSync(filePath, 'utf8');
  const relative = path.relative(root, filePath);

  const thTags = source.match(/<th\b[^>]*>/g) ?? [];
  if (thTags.some((tag) => !/\bscope=/.test(tag))) tableHeaderViolations.push(relative);

  const imgTags = source.match(/<img\b[^>]*>/g) ?? [];
  if (imgTags.some((tag) => !/\balt=/.test(tag))) imageAltViolations.push(relative);
}

if (tableHeaderViolations.length) {
  console.error(`Accessibility regression: table headers require scope attributes: ${tableHeaderViolations.join(', ')}`);
  process.exit(1);
}

if (imageAltViolations.length) {
  console.error(`Accessibility regression: image elements require alt text: ${imageAltViolations.join(', ')}`);
  process.exit(1);
}

console.log('Accessibility baseline checks passed.');
