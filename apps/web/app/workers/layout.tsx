import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Find flexible shift work in Singapore | QY Workforce',
  description:
    'Register interest for flexible hospitality, F&B, cleaning, retail, promotions and event shifts with QY Workforce.',
  alternates: { canonical: '/workers' },
  openGraph: {
    title: 'Find flexible shift work in Singapore | QY Workforce',
    description:
      'Register interest for flexible hospitality, F&B, cleaning, retail, promotions and event shifts with QY Workforce.',
    url: '/workers',
    type: 'website',
  },
};

export default function WorkersLayout({ children }: { children: ReactNode }) {
  return children;
}
