export function formatShiftTime(startsAt, endsAt) {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())) return 'Schedule unavailable';
  const date = new Intl.DateTimeFormat('en-SG', { day: 'numeric', month: 'short' }).format(start);
  const startTime = start.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit', hour12: false });
  const endTime = end.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit', hour12: false });
  return `${date} · ${startTime}–${endTime}`;
}

export function parseRequirements(value) {
  if (Array.isArray(value)) {
    return value.filter((item) => typeof item === 'string' && item.trim().length > 0).map((item) => item.trim());
  }
  if (value && typeof value === 'object') {
    return Object.entries(value)
      .filter(([, enabled]) => Boolean(enabled))
      .map(([label]) => label.replaceAll('_', ' '));
  }
  return [];
}

export function normalizeAvailableShift(row) {
  if (!row || typeof row !== 'object') return null;
  const id = typeof row.shift_id === 'string' ? row.shift_id : '';
  const startsAt = typeof row.starts_at === 'string' ? row.starts_at : '';
  const endsAt = typeof row.ends_at === 'string' ? row.ends_at : '';
  const startMs = Date.parse(startsAt);
  const endMs = Date.parse(endsAt);
  const slots = Number(row.available_slots ?? 0);

  // The backend remains authoritative for eligibility and availability. These checks only
  // prevent malformed or already-unavailable rows from becoming actionable mobile cards.
  if (!id || !Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) return null;
  if (!Number.isFinite(slots) || slots < 1) return null;

  const rate = Number(row.worker_rate ?? 0);
  return {
    id,
    role: typeof row.role_name === 'string' && row.role_name.trim() ? row.role_name : 'Shift',
    client: typeof row.client_name === 'string' ? row.client_name : '',
    site: typeof row.site_name === 'string' ? row.site_name : '',
    startsAt,
    endsAt,
    rate: Number.isFinite(rate) && rate >= 0 ? rate : 0,
    requirements: parseRequirements(row.requirements),
    availableSlots: Math.floor(slots),
  };
}

export function shiftAccessibilityLabel(shift) {
  const location = [shift.client, shift.site].filter(Boolean).join(', ');
  const slots = `${shift.availableSlots} slot${shift.availableSlots === 1 ? '' : 's'} remaining`;
  return [shift.role, location, formatShiftTime(shift.startsAt, shift.endsAt), `S$${shift.rate.toFixed(2)} per hour`, slots]
    .filter(Boolean)
    .join('. ');
}

export function shiftAcceptanceSummary(shift) {
  const location = [shift.client, shift.site].filter(Boolean).join(' · ');
  return [
    shift.role,
    location,
    formatShiftTime(shift.startsAt, shift.endsAt),
    `S$${shift.rate.toFixed(2)}/hr`,
  ].filter(Boolean).join('\n');
}
