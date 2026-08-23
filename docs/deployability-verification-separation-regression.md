# Deployability verification separation regression guard

QY Workforce treats identity verification, residency and legal work eligibility as separate evidence lifecycles.

## Deployability rule

`worker_has_deployment_prerequisites(worker_id)` must combine, rather than collapse, these controls:

- identity verification from the worker identity lifecycle;
- residency through `worker_has_current_residency`, including purpose-specific evidence freshness/expiry;
- work eligibility through `worker_has_current_work_eligibility`, including purpose-specific evidence freshness/expiry;
- current-version consent for identity verification, work eligibility and location clocking;
- active approved role, vetting state and required training.

The denormalised `worker_profiles.residency_verified` and `worker_profiles.work_eligibility` columns remain compatibility/current-state summaries. They must not replace the purpose-specific evidence helpers once separate evidence exists.

## Why this guard exists

The consent-version hardening migration re-issued the deployability predicate and unintentionally used the profile summary fields directly. That could allow stale or expired residency/work-eligibility evidence to be ignored after consent controls were upgraded.

Migration `202608231320_restore_separate_verification_deployability.sql` restores the evidence-aware helpers while preserving current-version consent checks.

`supabase/tests/deployability_verification_separation_regression_checks.sql` fails if a later migration again removes the independent residency or work-eligibility helpers, removes expiry-awareness, or drops the required current-consent checks.

## Provider boundary

This change does not enable production Singpass/MyInfo. Identity/residency/work-eligibility provider handling remains restricted to mock/staging/manual-review paths already defined by the backend migrations. No production credentials or raw provider payloads are introduced.
