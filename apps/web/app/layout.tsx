import type { Metadata } from 'next';
import React from 'react';

export const metadata: Metadata = {
  title: { default: 'QY Workforce | Flexible staffing for Singapore', template: '%s | QY Workforce' },
  description: 'Verified casual workers for hospitality, F&B, cleaning, retail, promotions and events.',
  metadataBase: new URL('https://workforce.qyvent.com'),
  openGraph: {
    title: 'QY Workforce | Flexible staffing for Singapore',
    description: 'Flexible staffing, verified workers and operational visibility.',
    type: 'website',
  },
  alternates: { canonical: '/' },
  robots: { index: true, follow: true },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: '#fff', color: '#101828', fontFamily: 'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' }}>
        {children}
      </body>
    </html>
  );
}
