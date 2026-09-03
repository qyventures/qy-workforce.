'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { safeOpsError } from '../../../lib/ops';

type Timesheet = { timesheet_id: string; exception_label: string; submitted_at: string };
type Correction = { request_id: string; requested_at: string; site_name: string; worker_label: string };

function errorMessage(error: { message: string } | null) {
  return safeOpsError(error, 'Unable to load live exceptions. No records were changed.');
}

export default function ExceptionsPage() {
  const [timesheets, setTimesheets] = useState<Timesheet[]>([]);
  const [corrections, setCorrections] = useState<Correction[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');

  async function load() {
    if (!supabase) {
      setLoading(false);
      setMessage('Live exception review is not configured in this deployment. Set the Supabase public environment variables for staging.');
      return;
    }
    setLoading(true);
    setMessage('');
    const [timesheetResult, correctionResult] = await Promise.all([
      supabase.rpc('get_timesheet_review_queue'),
      supabase.rpc('get_attendance_correction_review_queue'),
    ]);
    if (timesheetResult.error) setMessage(errorMessage(timesheetResult.error));
    else setTimesheets((timesheetResult.data ?? []) as Timesheet[]);
    if (correctionResult.error) setMessage((current) => current || errorMessage(correctionResult.error));
    else setCorrections((correctionResult.data ?? []) as Correction[]);
    setLoading(false);
  }

  useEffect(() => { void load(); }, []);

  const exceptionCounts = useMemo(() => {
    const counts = new Map<string, number>();
    timesheets.filter((row) => row.exception_label !== 'Clean').forEach((row) => {
      counts.set(row.exception_label, (counts.get(row.exception_label) ?? 0) + 1);
    });
    return [...counts.entries()];
  }, [timesheets]);

  const total = timesheets.filter((row) => row.exception_label !== 'Clean').length + corrections.length;

  return (
    <main style={styles.page}>
      <div style={styles.wrap}>
        <header style={styles.header}>
          <div><div style={styles.eyebrow}>OPERATIONS / EXCEPTIONS</div><h1 style={styles.h1}>Attendance & compliance exceptions</h1><p style={styles.sub}>Prioritised, site-scoped queues. Review the underlying approval request without exposing unrelated worker information.</p></div>
          <div style={styles.actions}><Link href="/ops" style={styles.button}>Operations</Link><button onClick={() => void load()} disabled={loading} style={styles.button}>{loading ? 'Refreshing…' : 'Refresh'}</button></div>
        </header>
        {message && <section role="status" style={styles.message}>{message}</section>}
        <section style={styles.metrics}><article style={styles.metric}><strong>{loading ? '—' : total}</strong><span> items needing review</span></article><article style={styles.metric}><strong>{loading ? '—' : corrections.length}</strong><span> attendance corrections</span></article><article style={styles.metric}><strong>{loading ? '—' : timesheets.filter((row) => row.exception_label !== 'Clean').length}</strong><span> timesheet exceptions</span></article></section>

        <section style={styles.panel}>
          <div style={styles.panelHeader}><div><h2 style={styles.h2}>Exception breakdown</h2><p style={styles.sub}>Counts come from the same masked review queue used by Timesheets.</p></div><Link href="/ops/timesheets" style={styles.link}>Open approval queue →</Link></div>
          {loading ? <p style={styles.empty}>Loading authorised exception queues…</p> : exceptionCounts.length === 0 && corrections.length === 0 ? <p style={styles.empty}>No live exceptions are visible to this account.</p> : <div style={styles.grid}>
            {exceptionCounts.map(([label, count]) => <article key={label} style={styles.card}><div style={styles.cardTop}><strong>{label}</strong><span style={styles.pill}>{count}</span></div><p>Submitted timesheet requiring supervisor or Ops review.</p><Link href="/ops/timesheets" style={styles.link}>Review timesheets →</Link></article>)}
            {corrections.length > 0 && <article style={styles.card}><div style={styles.cardTop}><strong>Attendance correction</strong><span style={styles.pill}>{corrections.length}</span></div><p>Pending requests to amend clock-in or clock-out evidence.</p><Link href="/ops/timesheets" style={styles.link}>Review corrections →</Link></article>}
          </div>}
        </section>
        <p style={styles.note}><strong>Security:</strong> live data is returned by server-side masked RPCs. This page is read-only; approvals and rejections remain inside the audited Timesheet RPC boundary.</p>
      </div>
    </main>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#f5f7fb', color: '#101828', padding: '32px 20px' }, wrap: { maxWidth: 1180, margin: '0 auto' }, header: { display: 'flex', justifyContent: 'space-between', alignItems: 'end', gap: 20, flexWrap: 'wrap', marginBottom: 20 }, eyebrow: { color: '#4d63ff', fontSize: 12, fontWeight: 800, letterSpacing: 1.2 }, h1: { fontSize: 32, margin: '6px 0' }, h2: { margin: 0, fontSize: 20 }, sub: { color: '#667085', margin: 0, lineHeight: 1.5 }, actions: { display: 'flex', gap: 8 }, button: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #d0d5dd', padding: '10px 13px', borderRadius: 10, background: '#fff', cursor: 'pointer', fontSize: 14 }, message: { padding: 14, background: '#eef2ff', color: '#3730a3', borderRadius: 12, marginBottom: 16 }, metrics: { display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12, marginBottom: 16 }, metric: { background: '#fff', border: '1px solid #e4e7ec', borderRadius: 14, padding: 18, color: '#667085' }, panel: { background: '#fff', border: '1px solid #e4e7ec', borderRadius: 16, padding: 20 }, panelHeader: { display: 'flex', justifyContent: 'space-between', gap: 14, alignItems: 'start', marginBottom: 16 }, grid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(230px,1fr))', gap: 12 }, card: { border: '1px solid #eaecf0', borderRadius: 12, padding: 16 }, cardTop: { display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center' }, pill: { padding: '4px 9px', borderRadius: 999, background: '#fff7ed', color: '#c2410c', fontWeight: 700, fontSize: 12 }, link: { color: '#344054', fontWeight: 700, textDecoration: 'none', fontSize: 13 }, empty: { color: '#667085', textAlign: 'center', padding: 28 }, note: { color: '#667085', fontSize: 12, lineHeight: 1.5, marginTop: 14 },
};
