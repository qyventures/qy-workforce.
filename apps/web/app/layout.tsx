import type { Metadata } from 'next';
import React from 'react';
import AnalyticsEvents from './analytics-events';

export const metadata: Metadata = {
  title: 'QY Workforce | Flexible staffing for Singapore',
  description: 'Verified casual workers for hospitality, F&B, cleaning, retail, promotions and events.',
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || 'https://workforce.qyvent.com'),
  openGraph: {
    title: 'QY Workforce',
    description: 'Flexible staffing, verified workers and operational visibility.',
    type: 'website',
  },
  robots: { index: true, follow: true },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: '#fff', color: '#101828', fontFamily: 'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' }}>
        <AnalyticsEvents />
        {children}
      </body>
    </html>
  );
}