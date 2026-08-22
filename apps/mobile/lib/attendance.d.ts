export type AttendanceLike = { clock_in_at?: string | null; clock_out_at?: string | null } | null;
export type TimesheetLike = { payable_minutes?: number | null; worker_amount?: number | null; status?: string | null } | null;

export function attendanceState(details: AttendanceLike): 'idle' | 'clocked-in' | 'clocked-out';
export function nextClockAction(details: AttendanceLike): 'in' | 'out' | null;
export function attendanceActionLabel(details: AttendanceLike): string;
export function formatRecordedPay(timesheet: TimesheetLike): string;
export function clockErrorMessage(message: unknown): string | null;
