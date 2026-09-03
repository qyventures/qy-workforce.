# Staging release checklist

Use only synthetic staging data and staging-only credentials. Do not copy production keys, identities, or customer data into any command, build environment, or test.

## Before building

- [ ] Use Node 22 (`.nvmrc`) and install each app's declared dependencies with its approved package manager.
- [ ] Configure `apps/mobile/.env.example` values in the EAS **preview** environment; configure `apps/web/.env.example` values in the staging host secret store. The service-role key is server-only.
- [ ] Run `node scripts/release/verify-release-readiness.mjs`.
- [ ] Apply Supabase migrations in ascending filename/version order. Do not edit an already-applied migration; add a newer migration instead.
- [ ] Run `scripts/release/run-supabase-checks.sh` with `STAGING_DATABASE_URL` supplied by the staging secret store. The checks are read-only except the audit-minimisation regression, which rolls its transaction back.

## Build and deploy

- [ ] Web: run `npm run typecheck` and `npm run build` from `apps/web`, then deploy the generated Next.js build through the approved staging host.
- [ ] Mobile: run `npm run typecheck` and `npm test` from `apps/mobile`.
- [ ] Build internal previews only: `eas build --platform android --profile preview` and `eas build --platform ios --profile preview` from `apps/mobile`. Android preview is an APK; iOS preview is an internal device build. Do not submit either build.
- [ ] Confirm the build is on the `preview` update channel and reports `EXPO_PUBLIC_APP_ENV=preview` where that value is surfaced.
- [ ] On both platforms, verify the worker can recover from an interrupted shift-feed/readiness request using the visible refresh action, and that session expiry returns to sign-in.
- [ ] Check TalkBack/VoiceOver labels and focus order for sign-in, readiness, shift acceptance, attendance clock actions, timesheet submission and sign-out.

## Smoke test and sign-off

- [ ] After deployment, run `STAGING_WEB_URL=https://staging.example.invalid scripts/release/run-staging-smoke.sh` with the real staging URL supplied only in the shell environment.
- [ ] Verify the complete synthetic-worker path: sign-in, onboarding, readiness, shift acceptance, attendance, timesheet submission, supervisor review, and payroll export preparation.
- [ ] Confirm the public lead endpoint returns a generic failure when its server-side key is intentionally absent, and succeeds only with staging configuration.
- [ ] Record migration versions, web commit/build identifier, EAS build IDs, tester, timestamp, and any known risks in the release ticket.

## Stop conditions

Do not advance a preview when migration ordering fails, RLS checks fail, a service-role key is exposed to a client bundle, production data is present, or web/mobile smoke tests fail.
