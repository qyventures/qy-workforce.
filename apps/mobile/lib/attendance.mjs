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
