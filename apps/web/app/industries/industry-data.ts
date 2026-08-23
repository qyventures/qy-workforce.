export type Industry = {
  id: string;
  name: string;
  roles: string[];
  employer: string;
  worker: string;
  proofPoints: string[];
};

export const industries: Industry[] = [
  {
    id: 'hospitality',
    name: 'Hospitality',
    roles: ['Banquet crew', 'Housekeeping support', 'Stewarding', 'Service crew', 'Guest-facing support'],
    employer: 'Scale around occupancy, banquets and peak periods while keeping worker readiness and attendance visible.',
    worker: 'See hospitality shifts that match your approved role and training readiness.',
    proofPoints: ['Role and site readiness before deployment', 'Attendance exceptions routed for review', 'Approved-hour reporting for payroll and billing'],
  },
  {
    id: 'food-beverage',
    name: 'Food & Beverage',
    roles: ['Service crew', 'Runners', 'Kitchen support', 'Cashier support', 'Peak-period crew'],
    employer: 'Add trained casual capacity for meal peaks, weekends and new-store demand without losing timesheet control.',
    worker: 'Access suitable service and kitchen-support shifts with clear site, timing and rate information.',
    proofPoints: ['Peak-hour staffing visibility', 'Supervisor approval before payable hours', 'Clear role, site and shift details for workers'],
  },
  {
    id: 'cleaning',
    name: 'Cleaning',
    roles: ['Commercial cleaners', 'Hotel room support', 'Public-area cleaners', 'Turnaround crew'],
    employer: 'Plan site coverage around defined roles and readiness while supervisors retain exception and approval control.',
    worker: 'Build role readiness once, then see cleaning assignments you are eligible to accept.',
    proofPoints: ['Qualification and training readiness', 'Structured attendance exception handling', 'Site-level fulfilment and margin visibility'],
  },
  {
    id: 'retail',
    name: 'Retail',
    roles: ['Sales support', 'Replenishment', 'Queue management', 'Seasonal crew', 'Stock support'],
    employer: 'Respond to launches, campaigns and seasonal peaks with structured attendance and approved-hour reporting.',
    worker: 'Choose retail shifts that fit your role eligibility and availability.',
    proofPoints: ['Multi-site deployment support', 'Approved worker eligibility by role', 'Attendance and fulfilment reporting by site'],
  },
  {
    id: 'promotions',
    name: 'Promotions & Roadshows',
    roles: ['Brand ambassadors', 'Promoters', 'Registration crew', 'Customer-acquisition support'],
    employer: 'Deploy campaign teams across sites with clearer fulfilment, attendance and approved-hour visibility.',
    worker: 'Discover event and roadshow opportunities with clear assignment details before accepting.',
    proofPoints: ['Campaign and site-level staffing visibility', 'Shift acceptance before deployment', 'Supervisor-reviewed attendance records'],
  },
  {
    id: 'events',
    name: 'Events',
    roles: ['Ushers', 'Registration crew', 'Event crew', 'Logistics support', 'Venue operations'],
    employer: 'Staff short-duration and high-headcount events while keeping site, attendance and supervisor review structured.',
    worker: 'Find event shifts aligned to your approved roles and deployment readiness.',
    proofPoints: ['High-headcount shift planning', 'Readiness and acceptance before deployment', 'Exception review and approved-hour controls'],
  },
];

export function getIndustry(id: string) {
  return industries.find((industry) => industry.id === id);
}
