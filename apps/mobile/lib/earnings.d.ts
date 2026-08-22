export function formatMoney(value: number | null | undefined): string;
export function payableDuration(minutes: number | null | undefined): string;
export function earningsBucket(status: string | null | undefined): 'approved' | 'pending' | 'rejected';
export function sumEarnings(rows: Array<{ timesheet?: { worker_amount?: number | null; status?: string | null } }>): { approved: number; pending: number };
