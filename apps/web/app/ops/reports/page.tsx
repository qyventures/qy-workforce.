'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type MarginRow = { site_id: string; site_name: string; client_id: string; client_name: string; shift_count: number; approved_hours: number; worker_cost: number; client_revenue: number; gross_margin: number; gross_margin_pct: number };

function isoDate(value: Date) { return value.toISOString().slice(0, 10); }
function currency(value: number) { return new Intl.NumberFormat('en-SG', { style: 'currency', currency: 'SGD' }).format(Number(value ?? 0)); }

export default function ReportsPage() {
  const now = new Date();
  const [start, setStart] = useState(isoDate(new Date(now.getFullYear(), now.getMonth(), 1)));
  const [end, setEnd] = useState(isoDate(now));
  const [rows, setRows] = useState<MarginRow[]>([]);
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const totals = useMemo(() => rows.reduce((total, row) => ({ hours: total.hours + Number(row.approved_hours), revenue: total.revenue + Number(row.client_revenue), cost: total.cost + Number(row.worker_cost) }), { hours: 0, revenue: 0, cost: 0 }), [rows]);
  const totalMargin = totals.revenue > 0 ? ((totals.revenue - totals.cost) / totals.revenue) * 100 : 0;

  async function load(event?: FormEvent) {
    event?.preventDefault();
    if (!supabase) { setMessage('Live reporting is disabled until the staging Supabase public environment is configured.'); return; }
    if (!start || !end || end < start) { setMessage('Choose a valid reporting period.'); return; }
    setLoading(true); setMessage('');
    const { data, error } = await supabase.rpc('get_site_margin_report', { p_start: start, p_end: end });
    setLoading(false);
    if (error) { setRows([]); setMessage('Sign in with an authorised Ops Manager, Finance, Admin or Auditor account to view the margin report.'); }
    else setRows((data ?? []) as MarginRow[]);
  }

  useEffect(() => { void load(); }, []);

  return <section style={styles.page}>
    <header style={styles.header}><div><div style={styles.eyebrow}>OPERATIONS / REPORTING</div><h1 style={styles.h1}>Fulfilment & margin</h1><p style={styles.sub}>Approved timesheet aggregates by client and site — never worker-level pay or identity data.</p></div></header>
    <form onSubmit={load} style={styles.controls}><label>From<input type="date" value={start} onChange={(e) => setStart(e.target.value)} style={styles.input}/></label><label>To<input type="date" value={end} onChange={(e) => setEnd(e.target.value)} style={styles.input}/></label><button disabled={loading} style={styles.primary}>{loading ? 'Loading…' : 'Run report'}</button></form>
    {message && <p aria-live="polite" style={styles.notice}>{message}</p>}
    <section style={styles.summary}><div><span>Approved hours</span><strong>{totals.hours.toFixed(1)}</strong></div><div><span>Client revenue</span><strong>{currency(totals.revenue)}</strong></div><div><span>Gross margin</span><strong>{currency(totals.revenue - totals.cost)} · {totalMargin.toFixed(1)}%</strong></div></section>
    <section style={styles.panel}>{rows.length === 0 ? <p style={styles.empty}>{loading ? 'Loading report…' : 'No approved timesheet aggregates are visible for this period.'}</p> : <div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr><th style={styles.th}>Client / site</th><th style={styles.th}>Shifts</th><th style={styles.th}>Approved hours</th><th style={styles.th}>Worker cost</th><th style={styles.th}>Revenue</th><th style={styles.th}>Gross margin</th></tr></thead><tbody>{rows.map((row) => <tr key={row.site_id}><td style={styles.strong}>{row.client_name}<br/><span style={styles.site}>{row.site_name}</span></td><td style={styles.td}>{row.shift_count}</td><td style={styles.td}>{Number(row.approved_hours).toFixed(1)}</td><td style={styles.td}>{currency(row.worker_cost)}</td><td style={styles.td}>{currency(row.client_revenue)}</td><td style={styles.td}><strong>{currency(row.gross_margin)}</strong><br/><span style={Number(row.gross_margin_pct) < 10 ? styles.low : styles.healthy}>{Number(row.gross_margin_pct).toFixed(1)}%</span></td></tr>)}</tbody></table></div>}</section>
    <p style={styles.foot}>The server-side report RPC enforces application-role access and returns aggregate economics only. Payroll exports remain restricted to Finance/Admin.</p>
  </section>;
}

const styles: Record<string, any> = { page: { minHeight: '100vh', padding: 32, background: '#F5F7FB', color: '#101828' }, header: { maxWidth: 1180, margin: '0 auto 18px' }, eyebrow: { color: '#4D63FF', fontSize: 12, fontWeight: 800, letterSpacing: 1.2 }, h1: { margin: '5px 0', fontSize: 32 }, sub: { color: '#667085', margin: 0 }, controls: { maxWidth: 1140, margin: '0 auto 16px', display: 'flex', gap: 12, alignItems: 'end', flexWrap: 'wrap' }, input: { display: 'block', marginTop: 6, border: '1px solid #D0D5DD', borderRadius: 9, padding: '9px 10px', fontSize: 14 }, primary: { border: 0, borderRadius: 9, padding: '11px 14px', background: '#111827', color: '#fff', fontWeight: 750, cursor: 'pointer' }, notice: { maxWidth: 1110, margin: '0 auto 16px', padding: 13, borderRadius: 10, background: '#EEF2FF', color: '#3730A3', fontSize: 13 }, summary: { maxWidth: 1140, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12 }, panel: { maxWidth: 1140, margin: '0 auto', padding: 20, background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16 }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#667085', padding: '10px 8px', borderBottom: '1px solid #EAECF0' }, td: { padding: '13px 8px', color: '#475467', borderBottom: '1px solid #F0F2F5' }, strong: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5' }, site: { color: '#98A2B3', fontWeight: 400 }, low: { color: '#B54708', fontWeight: 750 }, healthy: { color: '#027A48', fontWeight: 750 }, empty: { padding: 25, textAlign: 'center', color: '#667085' }, foot: { maxWidth: 1140, margin: '14px auto 0', color: '#98A2B3', fontSize: 12, lineHeight: 1.5 } };
