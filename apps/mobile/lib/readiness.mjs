export function normalizeWorkerStatus(value) {
  if (typeof value !== 'string') return 'PENDING';
  const normalized = value.trim().toUpperCase();
  return normalized || 'PENDING';
}

export function getReadinessChecks(state) {
  return [
    ['Identity verified', state?.identity_verified === true],
    ['Residency verified', state?.residency_verified === true],
    ['Eligible to work', state?.work_eligibility === 'eligible'],
    ['Approved role', Number(state?.approved_roles) > 0],
    ['Required training complete', Number(state?.outstanding_training) === 0],
    ['Vetting clear', Number(state?.failed_vetting) === 0],
    ['Required consent recorded', state?.required_consents_complete === true],
  ];
}

export function readinessSummary(state) {
  const checks = getReadinessChecks(state);
  const readyCount = checks.filter(([, ready]) => ready).length;
  return {
    checks,
    readyCount,
    totalCount: checks.length,
    statusLabel: state?.deployable === true ? 'DEPLOYABLE' : normalizeWorkerStatus(state?.worker_status),
  };
}
