import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Hire flexible workers in Singapore | QY Workforce',
  description:
    'Request verified flexible workers for hospitality, F&B, cleaning, retail, promotions and events in Singapore.',
  alternates: { canonical: '/employers' },
  openGraph: {
    title: 'Hire flexible workers in Singapore | QY Workforce',
    description:
      'Request verified flexible workers for hospitality, F&B, cleaning, retail, promotions and events in Singapore.',
    url: '/employers',
    type: 'website',
  },
};

export default function EmployersLayout({ children }: { children: ReactNode }) {
  return children;
}
