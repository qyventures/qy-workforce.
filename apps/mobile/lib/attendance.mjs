export function attendanceRouteMode(hasBackend, assignmentId) {
  if (!hasBackend) return 'demo';
  if (assignmentId === 'demo-assignment') return 'demo';
  if (typeof assignmentId !== 'string' || assignmentId.trim() === '') return 'invalid';
  return 'live';
}

export function attendanceState(details) {
  if (!details) return 'idle';
  if (details.clock_out_at) return 'clocked-out';
  if (details.clock_in_at) return 'clocked-in';
  return 'idle';
}

export function nextClockAction(details) {
  const state = attendanceState(details);
  if (state === 'clocked-out') return null;
  return state === 'clocked-in' ? 'out' : 'in';
}

export function attendanceActionLabel(details) {
  const action = nextClockAction(details);
  if (!action) return 'Shift completed';
  return action === 'out' ? 'Verify location & clock out' : 'Verify location & clock in';
}

function validDate(value) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

export function formatAttendanceSchedule(startsAt, endsAt) {
  const start = validDate(startsAt);
  const end = validDate(endsAt);
  if (!start || !end || end.getTime() <= start.getTime()) return 'Schedule unavailable';
  return `${start.toLocaleDateString([], { day: 'numeric', month: 'short' })} · ${start.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}–${end.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}

export function formatAttendanceTimestamp(value, fallback = 'Time unavailable') {
  const date = validDate(value);
  return date ? date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : fallback;
}

export function formatRecordedPay(timesheet) {
  if (!timesheet) return 'A draft timesheet is being prepared.';
  const rawMinutes = Number(timesheet.payable_minutes);
  const minutes = Number.isFinite(rawMinutes) && rawMinutes > 0 ? Math.floor(rawMinutes) : 0;
  const rawAmount = Number(timesheet.worker_amount);
  const amount = Number.isFinite(rawAmount) && rawAmount >= 0 ? rawAmount : 0;
  const status = typeof timesheet.status === 'string' && timesheet.status.trim() ? timesheet.status.trim() : 'pending';
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m recorded · Est. S$${amount.toFixed(2)} · ${status}`;
}

export function clockErrorMessage(message) {
  const text = typeof message === 'string' ? message.toLowerCase() : '';
  if (text.includes('outside approved worksite geofence')) {
    return 'You are outside the approved worksite area. Move closer to the worksite and try again.';
  }
  if (text.includes('location accuracy insufficient')) {
    return 'Your location is not accurate enough yet. Move to an open area and try again.';
  }
  return null;
}
