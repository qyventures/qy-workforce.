# Secure shift matching readiness

Shift discovery and acceptance use the same final live deployability check. An Ops-managed `deployable` profile status is necessary but not sufficient: identity, residency, time-bounded work eligibility, training, vetting and required consents are independently evaluated at the time of matching and again at acceptance. Table-level assignment activation repeats this boundary, so future privileged integrations cannot bypass it.

The internal `worker_is_available_for_shift` predicate also excludes a shift that overlaps a worker-declared `unavailable` window or a non-terminal absence (`reported`, `reviewed`, or `approved`). It does not disclose absence type, reason, medical detail, or document references to clients or other workers. A missing availability record means availability is unspecified rather than unavailable.

`get_available_shifts()` filters inactive role, site and client configurations before showing demand. `accept_shift()` repeats those checks under a shift-row lock, serializes a worker's concurrent acceptance/cancellation activity, rechecks capacity and schedule overlap, and audits only operational shift metadata. Ops replacement suggestions apply the same final deployability and absence/unavailability predicate, but remain decision support rather than assignment automation. This preserves a server-authoritative capacity boundary even if a mobile client is modified or its feed is stale.

Availability and absence information are scheduling data only. They must not be used as identity, residency, or work-eligibility evidence, and sensitive absence documentation remains behind privileged operations access.
