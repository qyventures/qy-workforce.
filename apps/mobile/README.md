# QY Workforce mobile

The Expo app is configured for internal staging pilots on iOS and Android. It talks only to the Supabase project specified at build time; it does not embed a project URL or key.

## Staging build checklist

1. In the EAS `preview` environment, set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` for the staging project only. The anonymous key is expected to be public, but all worker data access must remain protected by RLS and the worker RPCs.
2. Configure the staging SMS provider before testing phone sign-in. Do not use production SMS or Supabase credentials.
3. Build the internal `preview` profile. It is assigned the `staging` update channel and produces an Android APK; iOS uses an internal device build.
4. On a physical device, verify foreground location permission, Location Services disabled messaging, an outside-geofence rejection, and a refresh after an interrupted clock action.

Run the focused checks when dependencies are installed:

```sh
npm test
npm run typecheck
```
