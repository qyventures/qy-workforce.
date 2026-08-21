'use client';

import { FormEvent, useEffect, useState } from 'react';
import { supabase } from '../../../lib/supabase';

export default function OpsLogin() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [status, setStatus] = useState('');
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    if (!supabase) return;
    void supabase.auth.getSession().then(({ data }) => setSignedIn(Boolean(data.session)));
  }, []);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    if (!supabase) {
      setStatus('Staging Supabase environment is not configured.');
      return;
    }
    setStatus('Signing in…');
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      setStatus('Sign-in failed. Check the authorised staff account and try again.');
      return;
    }
    setSignedIn(true);
    setPassword('');
    setStatus('Signed in. Open the approval queue to continue.');
  }

  async function signOut() {
    if (!supabase) return;
    await supabase.auth.signOut();
    setSignedIn(false);
    setStatus('Signed out.');
  }

  return (
    <main style={styles.page}>
      <section style={styles.card}>
        <div style={styles.eyebrow}>QY WORKFORCE OPERATIONS</div>
        <h1 style={styles.h1}>Staff sign in</h1>
        <p style={styles.sub}>For authorised supervisors and operations personnel only.</p>

        {signedIn ? (
          <div style={styles.signedIn}>
            <p>You have an active staff session.</p>
            <a href="/ops/timesheets" style={styles.primary}>Open approval queue</a>
            <button onClick={() => void signOut()} style={styles.secondary}>Sign out</button>
          </div>
        ) : (
          <form onSubmit={signIn} style={styles.form}>
            <label style={styles.label}>Work email
              <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" autoComplete="username" required style={styles.input} />
            </label>
            <label style={styles.label}>Password
              <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" autoComplete="current-password" required minLength={8} style={styles.input} />
            </label>
            <button type="submit" style={styles.primaryButton}>Sign in securely</button>
          </form>
        )}

        {status && <p aria-live="polite" style={styles.status}>{status}</p>}
        <p style={styles.security}>Sessions use Supabase Auth and browser secure storage. Access to data is still enforced by database RLS and server-side RPC authorisation; signing in alone does not grant Ops privileges.</p>
      </section>
    </main>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 24, background: '#F5F7FB' },
  card: { width: '100%', maxWidth: 440, background: '#fff', border: '1px solid #E4E7EC', borderRadius: 20, padding: 28, boxShadow: '0 18px 50px rgba(16,24,40,.08)' },
  eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 },
  h1: { margin: '7px 0 6px', fontSize: 32, letterSpacing: '-.03em' },
  sub: { margin: '0 0 24px', color: '#667085' },
  form: { display: 'grid', gap: 16 },
  label: { display: 'grid', gap: 7, fontSize: 13, fontWeight: 700, color: '#344054' },
  input: { border: '1px solid #D0D5DD', borderRadius: 10, padding: '12px 13px', fontSize: 15, outline: 'none' },
  primaryButton: { border: 0, borderRadius: 10, padding: '12px 14px', background: '#111827', color: '#fff', fontWeight: 800, cursor: 'pointer' },
  primary: { display: 'block', textAlign: 'center', textDecoration: 'none', borderRadius: 10, padding: '12px 14px', background: '#111827', color: '#fff', fontWeight: 800 },
  secondary: { width: '100%', border: '1px solid #D0D5DD', borderRadius: 10, padding: '11px 14px', background: '#fff', color: '#344054', fontWeight: 700, cursor: 'pointer' },
  signedIn: { display: 'grid', gap: 10, color: '#344054' },
  status: { marginTop: 16, padding: 10, borderRadius: 9, background: '#F2F4F7', color: '#475467', fontSize: 13 },
  security: { margin: '20px 0 0', color: '#98A2B3', fontSize: 11, lineHeight: 1.55 },
};
