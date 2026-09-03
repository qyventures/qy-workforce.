'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '../../../lib/supabase';

type MarginRow = {
  site_id: string;
  site_name: string;
  client_id: string;
  client_name: string;
  shift_count: number;
  approved_hours: number;
  worker_cost: number;
  client_revenue: number;
  gross_margin: number;
  gross_margin_pct: number;
};

function monthStart() {
  const date = new Date();
  return new Date(date.getFullYear(), date.getMonth(), 1).toLocaleDateString('en-CA');
}

function today() {
  return new Date().toLocaleDateString('en-CA');
}

function money(value: number) {
  return `S$${Number(value || 0).toFixed(2)}`;
}

export default function ClientsPage() {
  const [start, setStart] = useState(monthStart);
  const [end, setEnd] = useState(today);
  const [rows, setRows] = useState<MarginRow[]>([]);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState('');

  async function load() {
    if (!supabase) return;
    if (!start || !end || end < start) {
      setMessage('Choose a valid reporting period.');
      return;
    }
    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_site_margin_report', { p_start: start, p_end: end });
    if (error) {
      setRows([]);
      setMessage(error.message.includes('authorised') || error.message.includes('authentication')
        ? 'Sign in with an authorised Ops, finance, admin or auditor account to view margin reporting.'
        : 'Unable to load the margin report. No financial records were changed.');
    } else setRows((data ?? []) as MarginRow[]);
    setLoading(false);
  }

  useEffect(() => { void load(); }, []);

  const totals = useMemo(() => rows.reduce((result, row) => ({
    shifts: result.shifts + Number(row.shift_count || 0),
    hours: result.hours + Number(row.approved_hours || 0),
    revenue: result.revenue + Number(row.client_revenue || 0),
    margin: result.margin + Number(row.gross_margin || 0),
  }), { shifts: 0, hours: 0, revenue: 0, margin: 0 }), [rows]);
  const marginPct = totals.revenue ? (totals.margin / totals.revenue) * 100 : 0;

  return <main style={styles.page}><div style={styles.wrap}>
    <header style={styles.header}><div><Link href="/ops" style={styles.back}>← Operations</Link><div style={styles.eyebrow}>OPERATIONS / CLIENTS & SITES</div><h1 style={styles.h1}>Client and site economics</h1><p style={styles.sub}>Aggregate approved-hours margin reporting. Worker identity and payroll details are never returned.</p></div><Link href="/ops/shifts" style={styles.button}>Manage shifts</Link></header>
    <section style={styles.controls}><label>From<input type="date" value={start} onChange={(event) => setStart(event.target.value)} /></label><label>To<input type="date" value={end} onChange={(event) => setEnd(event.target.value)} /></label><button onClick={() => void load()} disabled={!supabase || loading}>{loading ? 'Loading…' : 'Refresh report'}</button></section>
    {!supabase && <p style={styles.notice}>Staging Supabase is not configured, so live client and site economics are disabled.</p>}
    {message && <p role="status" style={styles.notice}>{message}</p>}
    <section style={styles.summary}><div><strong>{totals.shifts}</strong><span> approved shifts</span></div><div><strong>{totals.hours.toFixed(1)}</strong><span> approved hours</span></div><div><strong>{money(totals.revenue)}</strong><span> client revenue</span></div><div><strong>{money(totals.margin)} · {marginPct.toFixed(1)}%</strong><span> gross margin</span></div></section>
    <section style={styles.panel}><div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr>{['Client','Site','Shifts','Approved hours','Revenue','Worker cost','Gross margin'].map((heading) => <th key={heading} style={styles.th}>{heading}</th>)}</tr></thead><tbody>{loading ? <tr><td colSpan={7} style={styles.empty}>Loading authorised margin report…</td></tr> : rows.length === 0 ? <tr><td colSpan={7} style={styles.empty}>No approved financial activity is visible for this period.</td></tr> : rows.map((row) => <tr key={row.site_id}><td style={styles.strong}>{row.client_name}</td><td style={styles.td}>{row.site_name}</td><td style={styles.td}>{row.shift_count}</td><td style={styles.td}>{Number(row.approved_hours).toFixed(1)}</td><td style={styles.td}>{money(row.client_revenue)}</td><td style={styles.td}>{money(row.worker_cost)}</td><td style={styles.td}><strong>{money(row.gross_margin)}</strong><div style={styles.muted}>{Number(row.gross_margin_pct).toFixed(1)}%</div></td></tr>)}</tbody></table></div></section>
    <p style={styles.note}><strong>Control boundary:</strong> the server validates the privileged role, bounds the period to 366 days and audits each report access. This page is read-only; rates and financial snapshots cannot be edited here.</p>
  </div></main>;
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#f5f7fb', padding: '32px 20px', color: '#101828' }, wrap: { maxWidth: 1200, margin: '0 auto' }, header: { display: 'flex', justifyContent: 'space-between', alignItems: 'end', gap: 20, flexWrap: 'wrap', marginBottom: 20 }, back: { color: '#475569', textDecoration: 'none', fontWeight: 700 }, eyebrow: { color: '#4d63ff', fontSize: 12, fontWeight: 800, letterSpacing: 1.2, marginTop: 16 }, h1: { fontSize: 34, margin: '6px 0' }, sub: { color: '#667085', margin: 0 }, button: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #d0d5dd', padding: '10px 13px', borderRadius: 10, background: '#fff' }, controls: { display: 'flex', gap: 12, alignItems: 'end', flexWrap: 'wrap', marginBottom: 16 }, controlsLabel: { display: 'grid', gap: 5 }, input: { padding: 10 }, summary: { display: 'grid', gridTemplateColumns: 'repeat(4,minmax(0,1fr))', gap: 12, marginBottom: 16, color: '#667085', fontSize: 14 }, panel: { background: '#fff', border: '1px solid #e4e7ec', borderRadius: 16, padding: 20 }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#667085', padding: 10, borderBottom: '1px solid #eaecf0', whiteSpace: 'nowrap' }, td: { padding: 13, borderBottom: '1px solid #f1f5f9', color: '#475467' }, strong: { padding: 13, borderBottom: '1px solid #f1f5f9', fontWeight: 750 }, muted: { color: '#98a2b3', fontSize: 12, marginTop: 3 }, empty: { color: '#667085', padding: 28, textAlign: 'center' }, notice: { padding: 13, borderRadius: 12, background: '#eef2ff', color: '#3730a3' }, note: { color: '#667085', fontSize: 12, lineHeight: 1.5, marginTop: 14 },
};
