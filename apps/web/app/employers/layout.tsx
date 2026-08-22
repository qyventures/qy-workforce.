import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Hire flexible workers',
  description: 'Request casual manpower for hospitality, F&B, cleaning, retail, promotions and events in Singapore.',
  alternates: { canonical: '/employers' },
};

export default function EmployersLayout({ children }: { children: ReactNode }) { return children; }
