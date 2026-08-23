import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Trust & Compliance | QY Workforce',
  description:
    'How QY Workforce approaches worker verification, attendance integrity, privacy, access control and operational auditability.',
  alternates: { canonical: '/trust' },
  openGraph: {
    title: 'Trust & Compliance | QY Workforce',
    description:
      'Verification, privacy, least privilege and operational auditability across the QY Workforce platform.',
    url: '/trust',
    type: 'website',
  },
};

export default function TrustLayout({ children }: { children: React.ReactNode }) {
  return children;
}
