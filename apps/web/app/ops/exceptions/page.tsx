'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type ExceptionRow = {
  timesheet_id: string;
  worker_label: string;
  site_name: string;
  role_name: string;
  starts_at: string;
  ends_at: string;
  payable_minutes: number;
  exception_type: 'Geofence' | 'Duration';
  exception_detail: string;
};

export default function ExceptionsPage() {
  const [rows, setRows] = useState<ExceptionRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const counts = useMemo(() => ({ total: rows.length, geofence: rows.filter((row) => row.exception_type === 'Geofence').length, duration: rows.filter((row) => row.exception_type === 'Duration').length }), [rows]);

  async function load() {
    if (!supabase) {
      setMessage('Live exception review is disabled until the staging Supabase public environment is configured.');
      setLoading(false);
      return;
    }
    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_attendance_exception_queue');
    if (error) {
      setRows([]);
      setMessage('Sign in with an authorised supervisor or Ops account to view exceptions for your permitted sites.');
    } else setRows((data ?? []) as ExceptionRow[]);
    setLoading(false);
  }

  useEffect(() => { void load(); }, []);

  return <section style={styles.page}>
    <header style={styles.header}>
      <div><div style={styles.eyebrow}>OPERATIONS / EXCEPTIONS</div><h1 style={styles.h1}>Attendance exceptions</h1><p style={styles.sub}>Prioritised submitted records for your permitted sites. Worker identities and precise location data stay out of this queue.</p></div>
      <Link href="/ops/timesheets" style={styles.primary}>Open approval queue</Link>
    </header>
    <section style={styles.summary} aria-label="Exception summary"><div><strong>{counts.total}</strong><span> awaiting review</span></div><div><strong>{counts.geofence}</strong><span> geofence</span></div><div><strong>{counts.duration}</strong><span> duration</span></div></section>
    {message && <p aria-live="polite" style={styles.notice}>{message}</p>}
    <section style={styles.panel}>
      {loading ? <p style={styles.empty}>Loading authorised exceptions…</p> : rows.length === 0 ? <p style={styles.empty}>No attendance exceptions are currently visible to this account.</p> : <div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr><th style={styles.th}>Worker</th><th style={styles.th}>Site / role</th><th style={styles.th}>Scheduled</th><th style={styles.th}>Payable</th><th style={styles.th}>Exception</th><th style={styles.th}>Next step</th></tr></thead><tbody>{rows.map((row) => <tr key={row.timesheet_id}><td style={styles.strong}>{row.worker_label}</td><td style={styles.td}>{row.site_name}<br /><span style={styles.muted}>{row.role_name}</span></td><td style={styles.td}>{new Date(row.starts_at).toLocaleString()}<br /><span style={styles.muted}>Ends {new Date(row.ends_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span></td><td style={styles.td}>{Math.floor(row.payable_minutes / 60)}h {row.payable_minutes % 60}m</td><td style={styles.td}><span style={row.exception_type === 'Geofence' ? styles.high : styles.warn}>{row.exception_type}</span><br /><span style={styles.muted}>{row.exception_detail}</span></td><td style={styles.td}><Link href="/ops/timesheets" style={styles.review}>Review record</Link></td></tr>)}</tbody></table></div>}
    </section>
    <p style={styles.foot}>Approval or rejection is available only through the audited timesheet decision RPC, which rechecks supervisor site scope and separation of duties.</p>
  </section>;
}

const styles: Record<string, any> = {
  page: { padding: 32, minHeight: '100vh', background: '#F5F7FB', color: '#101828' }, header: { maxWidth: 1180, margin: '0 auto 20px', display: 'flex', justifyContent: 'space-between', alignItems: 'end', gap: 16, flexWrap: 'wrap' }, eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 }, h1: { margin: '5px 0', fontSize: 32 }, sub: { margin: 0, color: '#667085', maxWidth: 760 }, primary: { border: 0, borderRadius: 9, padding: '11px 14px', background: '#111827', color: '#fff', fontWeight: 750, textDecoration: 'none' }, summary: { maxWidth: 1140, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12, color: '#667085' }, notice: { maxWidth: 1110, margin: '0 auto 16px', padding: 13, borderRadius: 10, background: '#EEF2FF', color: '#3730A3', fontSize: 13 }, panel: { maxWidth: 1140, margin: '0 auto', padding: 20, background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16 }, empty: { padding: 28, textAlign: 'center', color: '#667085' }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#667085', padding: '10px 8px', borderBottom: '1px solid #EAECF0' }, td: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467', verticalAlign: 'top' }, strong: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', fontWeight: 750 }, muted: { color: '#98A2B3', fontSize: 12, lineHeight: 1.45 }, high: { display: 'inline-block', padding: '4px 8px', borderRadius: 999, background: '#FEF3F2', color: '#B42318', fontWeight: 700, fontSize: 12 }, warn: { display: 'inline-block', padding: '4px 8px', borderRadius: 999, background: '#FFFAEB', color: '#B54708', fontWeight: 700, fontSize: 12 }, review: { display: 'inline-block', padding: '7px 10px', border: '1px solid #D0D5DD', borderRadius: 8, color: '#344054', textDecoration: 'none', fontWeight: 700 }, foot: { maxWidth: 1140, margin: '14px auto 0', color: '#98A2B3', fontSize: 12, lineHeight: 1.5 },
};
