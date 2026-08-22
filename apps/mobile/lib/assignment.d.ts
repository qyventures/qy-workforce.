export function normalizeAssignmentSchedule(startsAt: string, endsAt: string): { start: Date; end: Date; durationMinutes: number } | null;
export function safeHourlyRate(value: unknown): number | null;
export function estimatedScheduledPay(durationMinutes: number, hourlyRate: unknown): number | null;
