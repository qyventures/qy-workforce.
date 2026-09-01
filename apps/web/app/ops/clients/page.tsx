'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
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

type BillingRow = {
  client_id: string;
  client_name: string;
  site_id: string;
  site_name: string;
  billing_status: string;
  item_count: number;
  billable_hours: number;
  worker_cost: number;
  client_revenue: number;
  gross_margin: number;
  gross_margin_pct: number;
};

function isoDate(date: Date) {
  return date.toLocaleDateString('en-CA');
}

function money(value: number) {
  return new Intl.NumberFormat('en-SG', { style: 'currency', currency: 'SGD' }).format(Number(value || 0));
}

export default function ClientsPage() {
  const [end, setEnd] = useState(() => isoDate(new Date()));
  const [start, setStart] = useState(() => {
    const date = new Date();
    date.setDate(date.getDate() - 29);
    return isoDate(date);
  });
  const [margins, setMargins] = useState<MarginRow[]>([]);
  const [billing, setBilling] = useState<BillingRow[]>([]);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState('');

  async function loadReports() {
    if (!supabase) {
      setLoading(false);
      return;
    }
    if (!start || !end || start > end) {
      setMessage('Choose an end date on or after the start date.');
      return;
    }
    const days = (Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000;
    if (days > 366) {
      setMessage('Reporting periods are limited to 366 days.');
      return;
    }
    setLoading(true);
    setMessage('');
    const [marginResult, billingResult] = await Promise.all([
      supabase.rpc('get_site_margin_report', { p_start: start, p_end: end }),
      supabase.rpc('get_client_billing_summary', { p_start: start, p_end: end }),
    ]);
    if (marginResult.error || billingResult.error) {
      setMargins([]);
      setBilling([]);
      const error = marginResult.error || billingResult.error;
      setMessage(error?.message.includes('authorised') || error?.message.includes('authentication')
        ? 'Sign in with an authorised Ops, Finance or Audit account to view aggregate client reporting.'
        : 'Unable to load aggregate client reporting. No financial data was changed.');
    } else {
      setMargins((marginResult.data ?? []) as MarginRow[]);
      setBilling((billingResult.data ?? []) as BillingRow[]);
    }
    setLoading(false);
  }

  useEffect(() => { void loadReports(); }, []);

  const summary = useMemo(() => {
    const revenue = margins.reduce((sum, row) => sum + Number(row.client_revenue || 0), 0);
    const margin = margins.reduce((sum, row) => sum + Number(row.gross_margin || 0), 0);
    return { sites: margins.length, revenue, margin, marginPct: revenue ? (margin / revenue) * 100 : 0 };
  }, [margins]);

  return <main style={styles.page}>
    <header style={styles.header}>
      <div><div style={styles.eyebrow}>OPERATIONS / CLIENTS & SITES</div><h1 style={styles.h1}>Client service & margin</h1><p style={styles.sub}>Aggregate service delivery, billing state and margin by client site. Worker identities and payroll details are excluded.</p></div>
      <div style={styles.actions}><Link href="/ops/planning" style={styles.secondary}>Fulfilment cockpit</Link><Link href="/ops" style={styles.secondary}>Overview</Link></div>
    </header>

    {!supabase && <section style={styles.notice}>Live reporting is not configured in this deployment. Configure the staging public Supabase variables and sign in; no demonstration financial figures are shown.</section>}
    {message && <section style={styles.message} role="status">{message}</section>}

    <section style={styles.filters} aria-label="Reporting period">
      <label style={styles.label}>From<input style={styles.input} type="date" value={start} max={end} onChange={(event) => setStart(event.target.value)} disabled={loading} /></label>
      <label style={styles.label}>To<input style={styles.input} type="date" value={end} min={start} max={isoDate(new Date())} onChange={(event) => setEnd(event.target.value)} disabled={loading} /></label>
      <button type="button" style={styles.primary} onClick={() => void loadReports()} disabled={!supabase || loading}>{loading ? 'Loading…' : 'Refresh report'}</button>
      <span style={styles.auditNote}>Each margin report view is audited server-side.</span>
    </section>

    <section style={styles.metrics} aria-label="Margin summary">
      <Metric label="Visible sites" value={String(summary.sites)} />
      <Metric label="Client revenue" value={money(summary.revenue)} />
      <Metric label="Gross margin" value={money(summary.margin)} />
      <Metric label="Gross margin rate" value={`${summary.marginPct.toFixed(1)}%`} />
    </section>

    <section style={styles.panel}>
      <h2 style={styles.h2}>Approved service margin</h2><p style={styles.panelSub}>Derived only from approved or payroll-ready timesheets in the selected period.</p>
      <ReportTable loading={loading} hasRows={margins.length > 0} empty="No approved service records are visible for this period.">
        <thead><tr>{['Client / site', 'Shifts', 'Approved hours', 'Revenue', 'Gross margin', 'GM rate'].map((label) => <th key={label} style={styles.th}>{label}</th>)}</tr></thead>
        <tbody>{margins.map((row) => <tr key={row.site_id}><td style={styles.td}><strong>{row.client_name}</strong><div style={styles.muted}>{row.site_name}</div></td><td style={styles.td}>{row.shift_count}</td><td style={styles.td}>{Number(row.approved_hours).toFixed(2)}</td><td style={styles.td}>{money(row.client_revenue)}</td><td style={styles.strong}>{money(row.gross_margin)}</td><td style={styles.strong}>{Number(row.gross_margin_pct).toFixed(1)}%</td></tr>)}</tbody>
      </ReportTable>
    </section>

    <section style={styles.panel}>
      <h2 style={styles.h2}>Client billing state</h2><p style={styles.panelSub}>Billing totals are aggregate control data. Invoice references and client contacts are not displayed here.</p>
      <ReportTable loading={loading} hasRows={billing.length > 0} empty="No billing items are visible for this period.">
        <thead><tr>{['Client / site', 'Billing state', 'Items', 'Billable hours', 'Revenue', 'GM rate'].map((label) => <th key={label} style={styles.th}>{label}</th>)}</tr></thead>
        <tbody>{billing.map((row) => <tr key={`${row.site_id}-${row.billing_status}`}><td style={styles.td}><strong>{row.client_name}</strong><div style={styles.muted}>{row.site_name}</div></td><td style={styles.td}><span style={styles.badge}>{row.billing_status.replaceAll('_', ' ')}</span></td><td style={styles.td}>{row.item_count}</td><td style={styles.td}>{Number(row.billable_hours).toFixed(2)}</td><td style={styles.td}>{money(row.client_revenue)}</td><td style={styles.strong}>{Number(row.gross_margin_pct).toFixed(1)}%</td></tr>)}</tbody>
      </ReportTable>
    </section>
    <p style={styles.note}>Access is enforced in the reporting RPCs for Ops Manager, Finance, Admin and Audit roles. Reports are aggregate-only and do not grant permission to change contracts, billing or payroll.</p>
  </main>;
}

function Metric({ label, value }: { label: string; value: string }) { return <article style={styles.metric}><div style={styles.muted}>{label}</div><strong style={styles.metricValue}>{value}</strong></article>; }
function ReportTable({ children, loading, hasRows, empty }: { children: ReactNode; loading: boolean; hasRows: boolean; empty: string }) { return loading ? <p style={styles.empty}>Loading authorised aggregate report…</p> : hasRows ? <div style={styles.tableWrap}><table style={styles.table}>{children}</table></div> : <p style={styles.empty}>{empty}</p>; }

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#F5F7FB', padding: '36px 22px 64px', color: '#101828' }, header: { maxWidth: 1180, margin: '0 auto 22px', display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'flex-start', flexWrap: 'wrap' }, eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 }, h1: { fontSize: 34, margin: '5px 0 6px', letterSpacing: '-.03em' }, h2: { margin: 0, fontSize: 20 }, sub: { margin: 0, color: '#667085', maxWidth: 700, lineHeight: 1.5 }, actions: { display: 'flex', gap: 8, flexWrap: 'wrap' }, secondary: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #D0D5DD', padding: '10px 13px', borderRadius: 10, background: '#fff' }, notice: { maxWidth: 1140, margin: '0 auto 14px', padding: 14, background: '#FFF7ED', border: '1px solid #FED7AA', borderRadius: 12, color: '#9A3412' }, message: { maxWidth: 1140, margin: '0 auto 14px', padding: 14, background: '#FEF2F2', border: '1px solid #FECACA', borderRadius: 12, color: '#B42318' }, filters: { maxWidth: 1140, margin: '0 auto 16px', display: 'flex', gap: 12, alignItems: 'end', flexWrap: 'wrap', background: '#fff', border: '1px solid #E4E7EC', borderRadius: 14, padding: 16 }, label: { display: 'grid', gap: 6, color: '#344054', fontSize: 13, fontWeight: 700 }, input: { padding: '10px 12px', border: '1px solid #D0D5DD', borderRadius: 9, fontSize: 14 }, primary: { border: 0, borderRadius: 9, padding: '11px 14px', background: '#111827', color: '#fff', fontWeight: 800, cursor: 'pointer' }, auditNote: { color: '#667085', fontSize: 12, paddingBottom: 3 }, metrics: { maxWidth: 1180, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 12 }, metric: { background: '#fff', border: '1px solid #E4E7EC', borderRadius: 14, padding: 16 }, metricValue: { display: 'block', marginTop: 7, fontSize: 23, letterSpacing: '-.02em' }, panel: { maxWidth: 1140, margin: '16px auto 0', background: '#fff', border: '1px solid #E4E7EC', borderRadius: 16, padding: 20 }, panelSub: { color: '#667085', fontSize: 13, margin: '5px 0 16px' }, tableWrap: { overflowX: 'auto' }, table: { width: '100%', borderCollapse: 'collapse', minWidth: 760, fontSize: 13 }, th: { textAlign: 'left', padding: '10px 8px', color: '#667085', borderBottom: '1px solid #EAECF0', fontSize: 12 }, td: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467' }, strong: { color: '#101828', fontWeight: 800 }, muted: { color: '#667085', fontSize: 12, marginTop: 3 }, badge: { display: 'inline-block', padding: '4px 8px', borderRadius: 999, background: '#F2F4F7', color: '#475467', textTransform: 'capitalize', fontSize: 12, fontWeight: 700 }, empty: { color: '#667085', padding: '16px 8px', margin: 0 }, note: { maxWidth: 1140, margin: '14px auto', color: '#667085', lineHeight: 1.5, fontSize: 12 },
};
