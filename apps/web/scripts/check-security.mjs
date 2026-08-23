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

const opsLayoutPath = path.join(root, 'app', 'ops', 'layout.tsx');
const opsLayout = fs.readFileSync(opsLayoutPath, 'utf8');
const requiredOpsMetadata = [
  'robots:',
  'index: false',
  'follow: false',
  'nocache: true',
  'noimageindex: true',
];
const missingOpsMetadata = requiredOpsMetadata.filter((snippet) => !opsLayout.includes(snippet));
if (missingOpsMetadata.length) {
  console.error(`Ops indexing regression: missing ${missingOpsMetadata.join(', ')}`);
  process.exit(1);
}

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const target = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(target);
    return /\.(?:js|jsx|mjs|ts|tsx)$/.test(entry.name) ? [target] : [];
  });
}

const sourceRoots = ['app', 'lib']
  .map((dir) => path.join(root, dir))
  .filter((dir) => fs.existsSync(dir));
const sourceFiles = sourceRoots.flatMap((dir) => walk(dir));

// Never allow a privileged Supabase credential to be exposed through a
// NEXT_PUBLIC_ variable. Server-only service-role usage is allowed in route
// handlers, but client components must never contain privileged key markers.
const publicSecretLeaks = sourceFiles.flatMap((file) => {
  const source = fs.readFileSync(file, 'utf8');
  return /NEXT_PUBLIC_[A-Z0-9_]*(?:SERVICE_ROLE|SERVICE_ROLE_KEY)/g.test(source)
    ? [path.relative(root, file)]
    : [];
});
if (publicSecretLeaks.length) {
  console.error(`Client secret regression: public privileged credential marker found in ${publicSecretLeaks.join(', ')}`);
  process.exit(1);
}

const forbiddenClientSecretMarkers = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'SERVICE_ROLE_KEY',
  'service_role',
  'service-role',
];
const clientSecretLeaks = sourceFiles.flatMap((file) => {
  const source = fs.readFileSync(file, 'utf8');
  const isClientComponent = /^\s*['"]use client['"];?/m.test(source);
  if (!isClientComponent) return [];
  return forbiddenClientSecretMarkers
    .filter((marker) => source.includes(marker))
    .map((marker) => `${path.relative(root, file)}:${marker}`);
});
if (clientSecretLeaks.length) {
  console.error(`Client secret regression: privileged Supabase/service-role marker found in ${clientSecretLeaks.join(', ')}`);
  process.exit(1);
}

// Ops writes must remain behind audited, authorization-aware RPCs. Direct table
// mutations from browser-facing Ops code can bypass workflow invariants even when
// RLS is present, so fail the build if insert/update/upsert/delete is chained from
// supabase.from(...). Read-only select queries remain allowed.
const opsRoot = path.join(root, 'app', 'ops');
const directMutationPattern = /\.from\s*\([^)]*\)[\s\S]{0,500}?\.(insert|update|upsert|delete)\s*\(/g;
const directOpsMutations = fs.existsSync(opsRoot)
  ? walk(opsRoot).flatMap((file) => {
      const source = fs.readFileSync(file, 'utf8');
      return [...source.matchAll(directMutationPattern)].map((match) =>
        `${path.relative(root, file)}:${match[1]}`,
      );
    })
  : [];

if (directOpsMutations.length) {
  console.error(
    `Ops least-privilege regression: direct table mutation found in ${directOpsMutations.join(', ')}. Use an audited server-side RPC instead.`,
  );
  process.exit(1);
}

// Public lead collection must remain constrained and non-cacheable. These checks
// do not exercise production credentials or submit any real lead data.
const leadRoutePath = path.join(root, 'app', 'api', 'leads', 'route.ts');
const leadRoute = fs.readFileSync(leadRoutePath, 'utf8');
const requiredLeadHardening = [
  'MAX_REQUEST_BYTES',
  '16 * 1024',
  "content-type",
  "application/json",
  'content-length',
  "request.headers.get('origin')",
  'request.nextUrl.origin',
  "'Cache-Control': 'no-store, max-age=0'",
  "'X-Content-Type-Options': 'nosniff'",
  'SUPABASE_SERVICE_ROLE_KEY',
];
const missingLeadHardening = requiredLeadHardening.filter((snippet) => !leadRoute.includes(snippet));
if (missingLeadHardening.length) {
  console.error(`Lead endpoint security regression: missing ${missingLeadHardening.join(', ')}`);
  process.exit(1);
}
if (/^\s*['"]use client['"];?/m.test(leadRoute)) {
  console.error('Lead endpoint security regression: service-role route must remain server-only.');
  process.exit(1);
}

// Conversion analytics must remain opt-in and respect browser privacy signals.
const analyticsPath = path.join(root, 'app', 'analytics-events.tsx');
const analyticsSource = fs.readFileSync(analyticsPath, 'utf8');
const requiredAnalyticsPrivacy = [
  "qy-workforce:analytics-consent",
  "=== 'granted'",
  'globalPrivacyControl',
  "doNotTrack === '1'",
];
const missingAnalyticsPrivacy = requiredAnalyticsPrivacy.filter((snippet) => !analyticsSource.includes(snippet));
if (missingAnalyticsPrivacy.length) {
  console.error(`Analytics privacy regression: missing ${missingAnalyticsPrivacy.join(', ')}`);
  process.exit(1);
}

console.log('Security headers, Ops indexing, client-secret boundaries, audited Ops mutations, lead hardening and analytics-consent checks passed.');
