# Privacy request lifecycle

QY Workforce handles worker privacy requests through audited RPCs rather than direct table mutation. This keeps access/export/erasure requests reviewable and prevents a client from bypassing retention or approval controls.

## State model

Allowed administrative transitions are:

- `submitted` -> `in_review` or `cancelled`
- `in_review` -> `approved`, `rejected`, or `cancelled`
- `approved` -> `completed`, `in_review`, or `cancelled`
- `rejected`, `completed`, and `cancelled` are terminal

An erasure request therefore cannot move directly from submission to completion. `approved -> in_review` is retained so an administrator can reopen review if a legal, payroll, dispute, fraud, or other retention concern appears before completion.

## Retention holds

A change to `retention_hold` requires a non-empty reason. An erasure request cannot be completed while a hold is active. This protects evidence that must remain available for legitimate operational or legal review while keeping the hold decision explicit and auditable.

The retention maintenance job already honours worker privacy-request holds when minimising location and identity-provider data. This migration does not add a new destructive deletion path.

## Erasure completion

Erasure completion requires:

1. prior review;
2. prior approval;
3. no active retention hold; and
4. a completion rationale/evidence note.

`completed` records administrative completion evidence. Actual minimisation or deletion remains governed by the separate retention implementation and applicable record-retention obligations.

## Audit and access controls

Only an authenticated `admin` application role may review requests. Direct authenticated insert/update/delete privileges on `privacy_requests` remain revoked. Every accepted transition emits `privacy_request.transitioned` with request type, old/new state, and hold-state change; the audit event contains no worker identity document numbers or provider payloads.

The RPC is `SECURITY DEFINER` with `search_path = public`, and the regression test verifies these invariants without production credentials.
