export function homeReadinessPresentation(value) {
  if (!value || typeof value !== 'object') {
    return { label: 'Check your verified status', detail: 'Open readiness to review your worker checks.', ready: false };
  }

  const deployable = value.deployable === true;
  const approvedRoles = Number.isFinite(Number(value.approved_roles)) && Number(value.approved_roles) >= 0
    ? Math.floor(Number(value.approved_roles))
    : 0;
  const outstandingTraining = Number.isFinite(Number(value.outstanding_training)) && Number(value.outstanding_training) >= 0
    ? Math.floor(Number(value.outstanding_training))
    : 0;

  if (deployable) {
    return {
      label: 'Ready for deployment',
      detail: approvedRoles > 0
        ? `${approvedRoles} approved role${approvedRoles === 1 ? '' : 's'} available for matching.`
        : 'Your verified worker checks are complete.',
      ready: true,
    };
  }

  if (outstandingTraining > 0) {
    return {
      label: 'Readiness checks pending',
      detail: `${outstandingTraining} training item${outstandingTraining === 1 ? '' : 's'} still outstanding.`,
      ready: false,
    };
  }

  return {
    label: 'Readiness checks pending',
    detail: 'Open readiness to see which verified checks still need attention.',
    ready: false,
  };
}
