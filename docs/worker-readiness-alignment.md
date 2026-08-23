# Worker readiness alignment

`get_worker_readiness()` is the worker-facing summary used by the mobile application. It must not report a worker as ready on weaker rules than secure shift acceptance.

The readiness RPC therefore delegates the final `deployable` decision to `worker_has_deployment_prerequisites(auth.uid())` and evaluates residency and work eligibility through their separate current-evidence helpers. It does not treat the denormalised `worker_profiles.residency_verified` or a stale `worker_profiles.work_eligibility = eligible` value as sufficient evidence.

The returned residency flag represents current, unexpired residency evidence. The returned work-eligibility value is `eligible` only when current work-eligibility evidence exists; terminal/manual-review states may still be surfaced from the profile summary, while stale historical eligibility falls back to `unknown`.

Required consent completeness uses the current effective policy version for identity verification, work eligibility and location clocking. Historical but superseded grants do not satisfy readiness.

Training readiness counts required active modules that do not have an unexpired passed completion. Approved-role counts ignore inactive roles, and verified-skill counts ignore inactive skills. Vetting blockers include pending, failed and manual-review outcomes, matching the authoritative deployment predicate.

The RPC keeps its existing result shape for mobile compatibility, remains `SECURITY DEFINER` with `search_path = public`, is executable only by authenticated users, and returns only the authenticated worker's own readiness state and non-sensitive counts.
