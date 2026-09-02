'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

const linkStyle = { color: '#475467', textDecoration: 'none', fontWeight: 650, fontSize: 14 };

export function SiteHeader() {
  return (
    <header style={{ borderBottom: '1px solid #EAECF0', background: '#fff' }}>
      <nav aria-label="Primary navigation" style={{ maxWidth: 1180, margin: '0 auto', minHeight: 68, padding: '0 24px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 18, flexWrap: 'wrap' }}>
        <Link href="/" style={{ color: '#101828', textDecoration: 'none', fontWeight: 850, letterSpacing: '.08em', fontSize: 14 }}>QY WORKFORCE</Link>
        <div style={{ display: 'flex', alignItems: 'center', gap: 18, flexWrap: 'wrap' }}>
          <Link href="/how-it-works" style={linkStyle}>How it works</Link>
          <Link href="/industries" style={linkStyle}>Industries</Link>
          <Link href="/workers" style={linkStyle}>Find shifts</Link>
          <Link href="/employers" style={{ background: '#101828', color: '#fff', textDecoration: 'none', borderRadius: 8, padding: '10px 13px', fontWeight: 750, fontSize: 14 }}>Hire workers</Link>
        </div>
      </nav>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer style={{ borderTop: '1px solid #EAECF0', background: '#fff' }}>
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '28px 24px', display: 'flex', justifyContent: 'space-between', gap: 20, flexWrap: 'wrap', color: '#667085', fontSize: 13 }}>
        <span>© {new Date().getFullYear()} QY Workforce</span>
        <div style={{ display: 'flex', gap: 18 }}><Link href="/privacy" style={linkStyle}>Privacy</Link><Link href="/terms" style={linkStyle}>Terms</Link></div>
      </div>
    </footer>
  );
}

/**
 * Sends only the event name and current path to an optional first-party endpoint.
 * No lead values, identifiers, cookies, or fingerprinting data are collected.
 */
export function trackConversion(event: string) {
  if (typeof window === 'undefined' || localStorage.getItem('qy-analytics-consent') !== 'granted') return;
  const endpoint = process.env.NEXT_PUBLIC_ANALYTICS_ENDPOINT;
  if (!endpoint) return;
  const payload = JSON.stringify({ event, path: window.location.pathname, at: new Date().toISOString() });
  navigator.sendBeacon?.(endpoint, new Blob([payload], { type: 'application/json' }));
}

export function ConsentBanner() {
  const [choice, setChoice] = useState<string | null>(null);
  useEffect(() => setChoice(localStorage.getItem('qy-analytics-consent')), []);
  if (choice) return null;
  const choose = (value: 'granted' | 'declined') => {
    localStorage.setItem('qy-analytics-consent', value);
    setChoice(value);
  };
  return (
    <aside aria-label="Analytics preference" style={{ position: 'fixed', zIndex: 20, right: 16, bottom: 16, maxWidth: 430, padding: 18, border: '1px solid #D0D5DD', borderRadius: 14, background: '#fff', boxShadow: '0 12px 28px rgba(16,24,40,.16)', color: '#344054', fontSize: 14, lineHeight: 1.5 }}>
      <strong style={{ color: '#101828' }}>Optional anonymous analytics</strong>
      <p style={{ margin: '7px 0 14px' }}>Help us understand page and button use. We never send form entries, names, emails, device IDs, or advertising cookies.</p>
      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
        <button type="button" onClick={() => choose('declined')} style={{ border: '1px solid #98A2B3', borderRadius: 8, background: '#fff', color: '#344054', padding: '8px 11px', fontWeight: 700 }}>No thanks</button>
        <button type="button" onClick={() => choose('granted')} style={{ border: 0, borderRadius: 8, background: '#101828', color: '#fff', padding: '8px 11px', fontWeight: 700 }}>Allow anonymous analytics</button>
      </div>
    </aside>
  );
}
