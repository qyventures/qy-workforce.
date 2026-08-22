export function formatMoney(value) {
  const amount = Number(value ?? 0);
  return `S$${Number.isFinite(amount) ? amount.toFixed(2) : '0.00'}`;
}

export function payableDuration(minutes) {
  const total = Math.max(0, Number(minutes) || 0);
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  return `${hours}h ${mins}m`;
}

export function earningsBucket(status) {
  if (status === 'approved' || status === 'payroll_ready' || status === 'paid') return 'approved';
  if (status === 'rejected') return 'rejected';
  return 'pending';
}

export function sumEarnings(rows) {
  return rows.reduce((totals, row) => {
    const amount = Number(row?.timesheet?.worker_amount ?? 0);
    const safeAmount = Number.isFinite(amount) ? amount : 0;
    const bucket = earningsBucket(row?.timesheet?.status);
    if (bucket === 'approved') totals.approved += safeAmount;
    if (bucket === 'pending') totals.pending += safeAmount;
    return totals;
  }, { approved: 0, pending: 0 });
}
