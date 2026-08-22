import Link from 'next/link';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Operations | QY Workforce',
  robots: {
    index: false,
    follow: false,
    nocache: true,
    googleBot: {
      index: false,
      follow: false,
      noimageindex: true,
    },
  },
};

const nav = [
  { href: '/ops', label: 'Command Centre' },
  { href: '/ops/shifts', label: 'Shifts' },
  { href: '/ops/workers', label: 'Workers' },
  { href: '/ops/clients', label: 'Clients & Sites' },
  { href: '/ops/exceptions', label: 'Exceptions' },
  { href: '/ops/timesheets', label: 'Timesheets' },
  { href: '/ops/payroll', label: 'Payroll' },
];

export default function OpsLayout({ children }: { children: ReactNode }) {
  return (
    <div style={{ minHeight: '100vh', background: '#0a0a0a', color: '#f5f5f5' }}>
      <header style={{ position: 'sticky', top: 0, zIndex: 20, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 24, padding: '16px 24px', borderBottom: '1px solid #252525', background: 'rgba(10,10,10,0.96)' }}>
        <div>
          <div style={{ fontSize: 12, letterSpacing: 1.2, color: '#9ca3af' }}>QY WORKFORCE</div>
          <div style={{ fontWeight: 700 }}>Operations</div>
        </div>
        <nav aria-label="Operations">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
            {nav.map((item) => (
              <Link key={item.href} href={item.href} style={{ color: '#f5f5f5', textDecoration: 'none', border: '1px solid #343434', borderRadius: 999, padding: '8px 12px', fontSize: 14 }}>
                {item.label}
              </Link>
            ))}
          </div>
        </nav>
      </header>
      <main>{children}</main>
    </div>
  );
}
