'use client';

import type { CSSProperties, FormEvent } from 'react';
import { useEffect, useMemo, useState } from 'react';
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

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

function defaultRange() {
  const end = new Date();
  const start = new Date();
  start.setDate(end.getDate() - 29);
  return { start: isoDate(start), end: isoDate(end) };
}

const stagingRows: MarginRow[] = [
  { site_id: 'staging-1', site_name: 'Marina Bay', client_id: 'staging-a', client_name: 'Harbour Hotel Group', shift_count: 48, approved_hours: 386.5, worker_cost: 5024.5, client_revenue: 6158.4, gross_margin: 1133.9, gross_margin_pct: 18.41 },
  { site_id: 'staging-2', site_name: 'Bugis', client_id: 'staging-b', client_name: 'City Living', shift_count: 31, approved_hours: 248, worker_cost: 3224, client_revenue: 4085.6, gross_margin: 861.6, gross_margin_pct: 21.09 },
  { site_id: 'staging-3', site_name: 'Orchard', client_id: 'staging-c', client_name: 'Lifestyle Retailer', shift_count: 22, approved_hours: 176, worker_cost: 2288, client_revenue: 2747.2, gross_margin: 459.2, gross_margin_pct: 16.71 },
];

export default function ClientsPage() {
  const initial = useMemo(defaultRange, []);
  const [start, setStart] = useState(initial.start);
  const [end, setEnd] = useState(initial.end);
  const [rows, setRows] = useState<MarginRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [mode, setMode] = useState<'live' | 'staging'>('staging');

  const totals = useMemo(() => rows.reduce((acc, row) => ({
    shifts: acc.shifts + Number(row.shift_count || 0),
    hours: acc.hours + Number(row.approved_hours || 0),
    cost: acc.cost + Number(row.worker_cost || 0),
    revenue: acc.revenue + Number(row.client_revenue || 0),
    margin: acc.margin + Number(row.gross_margin || 0),
  }), { shifts: 0, hours: 0, cost: 0, revenue: 0, margin: 0 }), [rows]);

  const portfolioMargin = totals.revenue > 0 ? (totals.margin / totals.revenue) * 100 : 0;

  async function loadReport(nextStart = start, nextEnd = end) {
    if (nextEnd < nextStart) {
      setMessage('End date must be on or after the start date.');
      return;
    }

    if (!supabase) {
      setRows(stagingRows);
      setMode('staging');
      setMessage('Showing staging figures because Supabase public staging variables are not configured in this build.');
      setLoading(false);
      return;
    }

    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_site_margin_report', { p_start: nextStart, p_end: nextEnd });
    if (error) {
      setRows([]);
      setMessage(error.message.includes('authorised') || error.message.includes('JWT')
        ? 'Sign in with an authorised Ops, Finance, Admin or Auditor account to view margin reporting.'
        : `Unable to load margin report: ${error.message}`);
    } else {
      setRows((data ?? []) as MarginRow[]);
      setMode('live');
    }
    setLoading(false);
  }

  useEffect(() => { void loadReport(initial.start, initial.end); }, [initial.end, initial.start]);

  function submit(event: FormEvent) {
    event.preventDefault();
    void loadReport();
  }

  return (
    <section style={styles.page}>
      <div style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS / CLIENTS & SITES</div>
          <h1 style={styles.h1}>Coverage & margin</h1>
          <p style={styles.sub}>Review approved labour economics by site without exposing worker identity or payroll-only data.</p>
        </div>
        <span style={mode === 'live' ? styles.liveBadge : styles.stagingBadge}>{mode === 'live' ? 'Live authorised data' : 'Staging data'}</span>
      </div>

      <form onSubmit={submit} style={styles.filters}>
        <label style={styles.label}>Start date<input aria-label="Margin report start date" type="date" value={start} onChange={(e) => setStart(e.target.value)} style={styles.input} /></label>
        <label style={styles.label}>End date<input aria-label="Margin report end date" type="date" value={end} onChange={(e) => setEnd(e.target.value)} style={styles.input} /></label>
        <button type="submit" disabled={loading} style={styles.button}>{loading ? 'Loading…' : 'Refresh report'}</button>
      </form>

      {message && <div role="status" style={styles.message}>{message}</div>}

      <div style={styles.cards}>
        <div style={styles.card}><span style={styles.cardLabel}>Approved hours</span><strong style={styles.cardValue}>{totals.hours.toFixed(1)}</strong></div>
        <div style={styles.card}><span style={styles.cardLabel}>Client revenue</span><strong style={styles.cardValue}>S${totals.revenue.toFixed(2)}</strong></div>
        <div style={styles.card}><span style={styles.cardLabel}>Gross margin</span><strong style={styles.cardValue}>S${totals.margin.toFixed(2)}</strong></div>
        <div style={styles.card}><span style={styles.cardLabel}>Portfolio GM</span><strong style={styles.cardValue}>{portfolioMargin.toFixed(1)}%</strong></div>
      </div>

      <div style={styles.panel}>
        {loading ? <p style={styles.empty}>Loading authorised margin report…</p> : rows.length === 0 ? <p style={styles.empty}>No approved/payroll-ready timesheets were found for this period.</p> : (
          <div style={{ overflowX: 'auto' }}>
            <table style={styles.table}>
              <thead><tr><th style={styles.th}>Client</th><th style={styles.th}>Site</th><th style={styles.th}>Shifts</th><th style={styles.th}>Approved hours</th><th style={styles.th}>Worker cost</th><th style={styles.th}>Revenue</th><th style={styles.th}>Gross margin</th><th style={styles.th}>GM %</th></tr></thead>
              <tbody>{rows.map((row) => (
                <tr key={row.site_id}>
                  <td style={styles.tdStrong}>{row.client_name}</td>
                  <td style={styles.td}>{row.site_name}</td>
                  <td style={styles.td}>{row.shift_count}</td>
                  <td style={styles.td}>{Number(row.approved_hours).toFixed(1)}</td>
                  <td style={styles.td}>S${Number(row.worker_cost).toFixed(2)}</td>
                  <td style={styles.td}>S${Number(row.client_revenue).toFixed(2)}</td>
                  <td style={styles.td}>S${Number(row.gross_margin).toFixed(2)}</td>
                  <td style={styles.td}><span style={Number(row.gross_margin_pct) >= 10 ? styles.good : styles.low}>{Number(row.gross_margin_pct).toFixed(1)}%</span></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </div>

      <p style={styles.note}>Security: reporting is produced by a privileged server-side RPC and contains site-level aggregates only. The browser never receives worker names, identity attributes or raw attendance coordinates from this view.</p>
    </section>
  );
}

const styles: Record<string, CSSProperties> = {
  page: { padding: 32, background: '#f5f7fb', minHeight: '100vh', color: '#101828' },
  header: { maxWidth: 1200, margin: '0 auto 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' },
  eyebrow: { color: '#4d63ff', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 },
  h1: { fontSize: 34, margin: '6px 0', letterSpacing: '-0.03em' },
  sub: { margin: 0, color: '#667085', maxWidth: 760 },
  liveBadge: { borderRadius: 999, padding: '7px 10px', background: '#ecfdf3', color: '#027a48', fontSize: 12, fontWeight: 750 },
  stagingBadge: { borderRadius: 999, padding: '7px 10px', background: '#fff7ed', color: '#b54708', fontSize: 12, fontWeight: 750 },
  filters: { maxWidth: 1200, margin: '0 auto 16px', display: 'flex', gap: 12, alignItems: 'flex-end', flexWrap: 'wrap' },
  label: { display: 'grid', gap: 6, color: '#475467', fontSize: 13, fontWeight: 650 },
  input: { minHeight: 44, border: '1px solid #d0d5dd', borderRadius: 10, background: '#fff', padding: '0 12px', fontSize: 16, color: '#101828' },
  button: { minHeight: 44, border: 0, borderRadius: 10, background: '#111827', color: '#fff', padding: '0 16px', fontWeight: 750, cursor: 'pointer' },
  message: { maxWidth: 1168, margin: '0 auto 16px', border: '1px solid #c7d2fe', borderRadius: 12, background: '#eef2ff', color: '#3730a3', padding: '12px 16px', fontSize: 13 },
  cards: { maxWidth: 1200, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 12 },
  card: { background: '#fff', border: '1px solid #e8ecf2', borderRadius: 14, padding: 16, display: 'grid', gap: 8 },
  cardLabel: { color: '#667085', fontSize: 12, fontWeight: 650 },
  cardValue: { fontSize: 24, letterSpacing: '-0.03em' },
  panel: { maxWidth: 1200, margin: '0 auto', background: '#fff', border: '1px solid #e8ecf2', borderRadius: 16, padding: 18 },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 },
  th: { textAlign: 'left', padding: '11px 9px', color: '#667085', borderBottom: '1px solid #eaecf0', whiteSpace: 'nowrap' },
  td: { padding: '13px 9px', borderBottom: '1px solid #f0f2f5', color: '#475467', whiteSpace: 'nowrap' },
  tdStrong: { padding: '13px 9px', borderBottom: '1px solid #f0f2f5', color: '#101828', fontWeight: 750, whiteSpace: 'nowrap' },
  good: { color: '#027a48', background: '#ecfdf3', borderRadius: 999, padding: '5px 8px', fontWeight: 750 },
  low: { color: '#b42318', background: '#fef3f2', borderRadius: 999, padding: '5px 8px', fontWeight: 750 },
  empty: { color: '#667085', textAlign: 'center', padding: 30 },
  note: { maxWidth: 1168, margin: '14px auto 0', color: '#667085', fontSize: 12, lineHeight: 1.5 },
};
