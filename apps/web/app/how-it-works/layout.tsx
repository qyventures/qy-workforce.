import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'How QY Workforce Works | Employers and Workers',
  description:
    'See how QY Workforce connects verified workers with employer shifts through readiness checks, matching, attendance, approvals and payroll-ready records.',
  alternates: { canonical: '/how-it-works' },
  openGraph: {
    title: 'How QY Workforce Works | Employers and Workers',
    description:
      'From staffing request to approved timesheet, QY Workforce connects employer demand with ready workers through a controlled workflow.',
    url: '/how-it-works',
    type: 'website',
  },
};

export default function HowItWorksLayout({ children }: { children: React.ReactNode }) {
  return children;
}
