import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Find flexible shifts | QY Workforce',
  description: 'Register your interest in flexible work across hospitality, F&B, cleaning, retail, promotions and events.',
  alternates: { canonical: '/workers' },
};

export default function WorkersLayout({ children }: Readonly<{ children: ReactNode }>) {
  return children;
}
