import type { Metadata } from 'next';
import React from 'react';

const canonicalSiteUrl = 'https://qyworkforce.com';

export const metadata: Metadata = {
  title: 'QY Workforce | Flexible staffing for Singapore',
  description: 'Verified casual workers for hospitality, F&B, cleaning, retail, promotions and events.',
  metadataBase: new URL(canonicalSiteUrl),
  alternates: {
    canonical: '/',
  },
  openGraph: {
    title: 'QY Workforce',
    description: 'Flexible staffing, verified workers and operational visibility.',
    type: 'website',
    url: canonicalSiteUrl,
    siteName: 'QY Workforce',
  },
  twitter: { card: 'summary_large_image', title: 'QY Workforce | Flexible staffing for Singapore', description: 'Flexible staffing, clear expectations and operational visibility for employers and workers.' },
  robots: { index: true, follow: true },
  category: 'staffing',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, background: '#fff', color: '#101828', fontFamily: 'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif' }}>
        <style>{`a:focus-visible, button:focus-visible, input:focus-visible, textarea:focus-visible, select:focus-visible, summary:focus-visible { outline: 3px solid #4D63FF; outline-offset: 3px; } a[href="#main-content"]:focus-visible { left: 8px !important; }`}</style>
        {children}
      </body>
    </html>
  );
}
