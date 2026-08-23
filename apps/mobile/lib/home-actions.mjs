export const HOME_ACTIONS = [
  { title: 'Find shifts', body: 'Browse eligible jobs matched to your verified roles and skills.', href: '/shifts' },
  { title: 'My shifts', body: 'See accepted work, attendance status and submitted timesheets.', href: '/my-shifts' },
  { title: 'Earnings', body: 'Track estimated earnings and timesheet payment status in one place.', href: '/earnings' },
  { title: 'Clock in / out', body: 'Open an accepted shift first, then start attendance for that assignment.', href: '/my-shifts' },
  { title: 'Updates', body: 'Open trusted shift, attendance and readiness reminders in one place.', href: '/notifications' },
  { title: 'Readiness', body: 'See identity, eligibility, role, vetting, training and consent checks in one place.', href: '/readiness' },
  { title: 'Profile & training', body: 'Complete onboarding, verification, certificates and required training.', href: '/onboarding' },
];

export function homeAction(title) {
  return HOME_ACTIONS.find(action => action.title === title) ?? null;
}
