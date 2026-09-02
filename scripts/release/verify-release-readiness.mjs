#!/usr/bin/env node

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../..');
const failures = [];

function requireFile(relativePath) {
  if (!existsSync(join(root, relativePath))) failures.push(`Missing ${relativePath}`);
}

for (const file of [
  'apps/mobile/.env.example',
  'apps/web/.env.example',
  'apps/mobile/eas.json',
  'docs/STAGING_RELEASE_CHECKLIST.md',
  'scripts/release/run-staging-seed.sh',
  'supabase/seed/staging.sql',
]) {
  requireFile(file);
}

const migrationsDirectory = join(root, 'supabase/migrations');
const migrations = readdirSync(migrationsDirectory)
  .filter((file) => file.endsWith('.sql'))
  .sort();
let previousVersion = -1n;
const versions = new Set();
for (const migration of migrations) {
  const match = /^(\d+)_[-a-z0-9_]+\.sql$/i.exec(migration);
  if (!match) {
    failures.push(`Invalid migration filename: ${migration}`);
    continue;
  }
  const version = BigInt(match[1]);
  if (versions.has(match[1])) failures.push(`Duplicate migration version: ${match[1]}`);
  if (version <= previousVersion) failures.push(`Migration order is not strictly increasing: ${migration}`);
  versions.add(match[1]);
  previousVersion = version;
}

if (migrations.length === 0) failures.push('No Supabase migrations found');

const testsDirectory = join(root, 'supabase/tests');
const tests = existsSync(testsDirectory)
  ? readdirSync(testsDirectory).filter((file) => file.endsWith('.sql')).sort()
  : [];
if (tests.length === 0) failures.push('No Supabase regression checks found');

if (existsSync(join(root, 'apps/mobile/eas.json'))) {
  const eas = JSON.parse(readFileSync(join(root, 'apps/mobile/eas.json'), 'utf8'));
  const preview = eas.build?.preview;
  if (preview?.distribution !== 'internal' || preview?.environment !== 'preview' || preview?.channel !== 'preview') {
    failures.push('EAS preview must use internal distribution, the preview environment, and preview channel');
  }
  if (preview?.android?.buildType !== 'apk') failures.push('EAS preview Android must produce an APK');
  if (preview?.ios?.simulator !== false) failures.push('EAS preview iOS must produce a device build');
}

if (failures.length) {
  console.error('Release readiness check failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`Release readiness check passed (${migrations.length} ordered migrations, ${tests.length} SQL checks).`);
}
