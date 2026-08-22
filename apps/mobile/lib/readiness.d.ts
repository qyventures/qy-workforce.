export type ReadinessCheck = readonly [string, boolean];

export function normalizeWorkerStatus(value: unknown): string;
export function getReadinessChecks(state: Record<string, unknown> | null | undefined): ReadinessCheck[];
export function readinessSummary(state: Record<string, unknown> | null | undefined): {
  checks: ReadinessCheck[];
  readyCount: number;
  totalCount: number;
  statusLabel: string;
};
