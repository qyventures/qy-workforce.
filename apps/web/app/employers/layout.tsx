import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Hire flexible workers | QY Workforce',
  description: 'Tell QY Workforce about your role, site, headcount and timing for flexible staffing support in Singapore.',
  alternates: { canonical: '/employers' },
};

export default function EmployersLayout({ children }: Readonly<{ children: ReactNode }>) {
  return children;
}
