export function normalizeAssignmentSchedule(startsAt, endsAt) {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const startMs = start.getTime();
  const endMs = end.getTime();

  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
    return null;
  }

  return {
    start,
    end,
    durationMinutes: Math.max(0, Math.round((endMs - startMs) / 60000)),
  };
}

export function safeHourlyRate(value) {
  if (value === null || value === undefined || value === '') return null;
  const rate = Number(value);
  return Number.isFinite(rate) && rate >= 0 ? rate : null;
}

export function estimatedScheduledPay(durationMinutes, hourlyRate) {
  if (!Number.isFinite(durationMinutes) || durationMinutes < 0) return null;
  const rate = safeHourlyRate(hourlyRate);
  if (rate === null) return null;
  return (durationMinutes / 60) * rate;
}
