import Link from 'next/link';
import { SiteFooter, SiteHeader } from './components/site-shell';

export default function NotFound() {
  return <main id="main-content" style={{ minHeight: '100vh', background: '#F9FAFB', color: '#101828' }}>
    <SiteHeader />
    <section style={{ maxWidth: 760, margin: '0 auto', padding: 'clamp(80px, 14vw, 150px) 24px', textAlign: 'center' }}>
      <p style={{ color: '#667085', fontSize: 13, fontWeight: 800, letterSpacing: 1.5 }}>404 · PAGE NOT FOUND</p>
      <h1 style={{ fontSize: 'clamp(42px, 7vw, 72px)', letterSpacing: '-.05em', lineHeight: 1, margin: '14px 0 18px' }}>Let’s get you back on track.</h1>
      <p style={{ color: '#475467', lineHeight: 1.6, fontSize: 18, margin: '0 auto 28px', maxWidth: 560 }}>The page may have moved. Choose a path to explore flexible staffing or work opportunities.</p>
      <div style={{ display: 'flex', justifyContent: 'center', gap: 12, flexWrap: 'wrap' }}>
        <Link href="/employers" style={{ background: '#101828', color: '#fff', padding: '13px 18px', borderRadius: 10, textDecoration: 'none', fontWeight: 800 }}>Hire workers</Link>
        <Link href="/workers" style={{ background: '#fff', border: '1px solid #D0D5DD', color: '#344054', padding: '13px 18px', borderRadius: 10, textDecoration: 'none', fontWeight: 800 }}>Find shifts</Link>
      </div>
    </section>
    <SiteFooter />
  </main>;
}
