import Link from 'next/link';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import styles from './layout.module.css';

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
  { href: '/ops/approvals', label: 'Approvals' },
  { href: '/ops/timesheets', label: 'Timesheets' },
  { href: '/ops/reports', label: 'Fulfilment & Margin' },
  { href: '/ops/payroll', label: 'Payroll' },
];

export default function OpsLayout({ children }: { children: ReactNode }) {
  return (
    <div className={styles.shell}>
      <a href="#ops-main" className={styles.skipLink}>Skip to operations content</a>
      <header className={styles.header}>
        <div>
          <div className={styles.brandEyebrow}>QY WORKFORCE</div>
          <div className={styles.brandTitle}>Operations</div>
        </div>
        <nav aria-label="Operations" className={styles.nav}>
          <div className={styles.navList}>
            {nav.map((item) => (
              <Link key={item.href} href={item.href} className={styles.navLink}>
                {item.label}
              </Link>
            ))}
          </div>
        </nav>
      </header>
      <main id="ops-main" tabIndex={-1} className={styles.main}>{children}</main>
    </div>
  );
}
