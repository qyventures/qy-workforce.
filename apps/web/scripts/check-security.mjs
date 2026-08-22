import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.cwd());
const configPath = path.join(root, 'next.config.ts');
const config = fs.readFileSync(configPath, 'utf8');

const requiredSnippets = [
  "X-Content-Type-Options",
  "nosniff",
  "Referrer-Policy",
  "strict-origin-when-cross-origin",
  "X-Frame-Options",
  "DENY",
  "Permissions-Policy",
  "frame-ancestors 'none'",
  "object-src 'none'",
  "Cache-Control",
  "no-store, max-age=0",
  "X-Robots-Tag",
  "noindex, nofollow, noarchive",
  "Strict-Transport-Security",
];

const missing = requiredSnippets.filter((snippet) => !config.includes(snippet));
if (missing.length) {
  console.error(`Security header regression: missing ${missing.join(', ')}`);
  process.exit(1);
}

const productionScriptSource = config.match(/const scriptSrc = isProduction\s*\?\s*"([^"]+)"/s)?.[1] ?? '';
if (!productionScriptSource || productionScriptSource.includes("'unsafe-eval'")) {
  console.error('Security header regression: production script-src must not allow unsafe-eval.');
  process.exit(1);
}

console.log('Security header checks passed.');
