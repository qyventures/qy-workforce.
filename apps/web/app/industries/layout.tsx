import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Industries | QY Workforce',
  description:
    'Flexible staffing for hospitality, F&B, cleaning, retail, promotions and events with readiness, attendance and approval controls built in.',
  alternates: { canonical: '/industries' },
  openGraph: {
    title: 'Industries | QY Workforce',
    description:
      'Flexible workforce operations for hospitality, F&B, cleaning, retail, promotions and events.',
    url: '/industries',
    type: 'website',
  },
};

export default function IndustriesLayout({ children }: { children: React.ReactNode }) {
  return children;
}
