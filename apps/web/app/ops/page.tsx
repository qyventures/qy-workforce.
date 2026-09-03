'use client';

import { useCallback, useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

type Cockpit = {
  as_of: string;
  active_jobs: number;
  active_required_headcount: number;
  active_filled_headcount: number;
  checked_in_workers: number;
  upcoming_jobs_7d: number;
  unassigned_jobs_7d: number;
  live_headcount_gap: number;
  sla_risk_jobs_72h: number;
  fulfilment_percent_7d: number;
  pending_labour_requisitions: number;
  submitted_timesheets: number;
  approved_timesheets_unbatched_exposure: number;
  locked_payroll_exposure: number;
  pending_billing_items: number;
  invoice_ready_items: number;
  billing_disputes: number;
  month_revenue: number;
  month_gross_margin: number;
  month_gross_margin_pct: number;
};

const demo: Cockpit = {
  as_of: new Date().toISOString(), active_jobs: 7, active_required_headcount: 128,
  active_filled_headcount: 121, checked_in_workers: 112, upcoming_jobs_7d: 42,
  unassigned_jobs_7d: 4, live_headcount_gap: 7, sla_risk_jobs_72h: 3,
  fulfilment_percent_7d: 91, pending_labour_requisitions: 5, submitted_timesheets: 19,
  approved_timesheets_unbatched_exposure: 0, locked_payroll_exposure: 0,
  pending_billing_items: 8, invoice_ready_items: 12, billing_disputes: 2,
  month_revenue: 0, month_gross_margin: 0, month_gross_margin_pct: 0,
};

const number = (value: number | null | undefined) => Number(value ?? 0).toLocaleString('en-SG');
const money = (value: number | null | undefined) => `S$${Number(value ?? 0).toLocaleString('en-SG', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export default function OpsDashboard() {
  const [cockpit, setCockpit] = useState<Cockpit | null>(supabase ? null : demo);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState('');

  const load = useCallback(async () => {
    if (!supabase) return;
    setLoading(true); setMessage('');
    const { data, error } = await supabase.rpc('get_management_cockpit', { p_as_of: new Date().toISOString() });
    if (error) {
      setMessage(error.message.includes('not authorised') || error.message.includes('authentication')
        ? 'Sign in with an authorised Ops, finance, admin or auditor account to view live indicators.'
        : 'Live command-centre data could not be loaded. Try again shortly.');
      setCockpit(null);
    } else setCockpit(data as Cockpit);
    setLoading(false);
  }, []);

  useEffect(() => { void load(); }, [load]);

  return <main style={styles.page}>
    <aside style={styles.sidebar}>
      <div style={styles.brand}>QY <span style={{ opacity: 0.62 }}>Workforce</span></div>
      <nav style={styles.nav}>
        {[['/ops','Overview'],['/ops/shifts','Shifts'],['/ops/workers','Workers'],['/ops/clients','Clients & sites'],['/ops/timesheets','Timesheets'],['/ops/payroll','Payroll export'],['/ops/planning','Planning'],['/ops/exceptions','Exceptions']].map(([href, label]) => <a key={href} href={href} style={href === '/ops' ? styles.navActive : styles.navItem}>{label}</a>)}
      </nav>
    </aside>

    <section style={styles.content}>
      <header style={styles.header}>
        <div><div style={styles.eyebrow}>OPERATIONS</div><h1 style={styles.h1}>Workforce command centre</h1><p style={styles.subtitle}>Live staffing, attendance, approvals, payroll exposure and billing indicators.</p></div>
        <div style={styles.headerActions}><button onClick={() => void load()} disabled={loading} style={styles.ghostButton}>{loading ? 'Refreshing…' : 'Refresh'}</button><a href="/ops/shifts" style={styles.primaryButton}>Manage shifts</a></div>
      </header>

      {!supabase && <div style={styles.notice}>Supabase is not configured in this deployment. Showing labelled demonstration data only.</div>}
      {message && <div style={styles.error} role="alert">{message}</div>}
      {loading && <div style={styles.notice}>Loading authorised live indicators…</div>}
      {cockpit && <>
        <div style={styles.metricGrid}>
          <Metric label="Live jobs" value={number(cockpit.active_jobs)} sub={`${number(cockpit.active_filled_headcount)} of ${number(cockpit.active_required_headcount)} workers filled`} />
          <Metric label="Checked in now" value={number(cockpit.checked_in_workers)} sub={`${number(cockpit.live_headcount_gap)} live headcount gap`} />
          <Metric label="7-day fulfilment" value={`${Number(cockpit.fulfilment_percent_7d).toFixed(1)}%`} sub={`${number(cockpit.unassigned_jobs_7d)} upcoming jobs with gaps`} />
          <Metric label="SLA risk · next 72h" value={number(cockpit.sla_risk_jobs_72h)} sub={`${number(cockpit.upcoming_jobs_7d)} jobs in next 7 days`} />
        </div>

        <div style={styles.twoCol}>
          <section style={styles.panel}><div style={styles.panelTitle}>Approval & staffing queue</div><div style={styles.panelSub}>Aggregates from the authorised management cockpit.</div><div style={styles.rows}>
            <Row label="Submitted timesheets" value={number(cockpit.submitted_timesheets)} href="/ops/timesheets" />
            <Row label="Pending labour requisitions" value={number(cockpit.pending_labour_requisitions)} href="/ops/shifts" />
            <Row label="Unbatched approved pay" value={money(cockpit.approved_timesheets_unbatched_exposure)} href="/ops/payroll" />
          </div></section>
          <section style={styles.panel}><div style={styles.panelTitle}>Billing & margin</div><div style={styles.panelSub}>Month-to-date financial indicators.</div><div style={styles.rows}>
            <Row label="Revenue" value={money(cockpit.month_revenue)} />
            <Row label="Gross margin" value={`${money(cockpit.month_gross_margin)} (${Number(cockpit.month_gross_margin_pct).toFixed(1)}%)`} />
            <Row label="Billing disputes" value={number(cockpit.billing_disputes)} href="/ops/reconciliation" warn />
          </div></section>
        </div>
        <section style={styles.panel}><div style={styles.panelHeader}><div><div style={styles.panelTitle}>Next actions</div><div style={styles.panelSub}>Prioritised operational signals; resolving them remains inside existing audited workflows.</div></div></div><div style={styles.actionGrid}><Action label="Live headcount gap" value={number(cockpit.live_headcount_gap)} href="/ops/exceptions" /><Action label="Invoice-ready items" value={number(cockpit.invoice_ready_items)} href="/ops/reconciliation" /><Action label="Pending billing items" value={number(cockpit.pending_billing_items)} href="/ops/reconciliation" /></div></section>
        <p style={styles.disclaimer}>As of {new Date(cockpit.as_of).toLocaleString('en-SG')}. Live data is read through a role-scoped, read-only RPC; workflow actions continue through their dedicated audited RPCs.</p>
      </>}
    </section>
  </main>;
}

function Metric({ label, value, sub }: { label: string; value: string; sub: string }) { return <article style={styles.metricCard}><div style={styles.metricLabel}>{label}</div><div style={styles.metricValue}>{value}</div><div style={styles.metricSub}>{sub}</div></article>; }
function Row({ label, value, href, warn }: { label: string; value: string; href?: string; warn?: boolean }) { const content = <><span>{label}</span><strong style={warn ? styles.warn : undefined}>{value}</strong></>; return href ? <a href={href} style={styles.row}>{content}</a> : <div style={styles.row}>{content}</div>; }
function Action({ label, value, href }: { label: string; value: string; href: string }) { return <a href={href} style={styles.action}><span>{label}</span><strong>{value}</strong><small>Review →</small></a>; }

const styles: Record<string, any> = {
  page: { margin: 0, minHeight: '100vh', background: '#F5F7FB', color: '#101828', fontFamily: 'Inter, ui-sans-serif, system-ui, sans-serif', display: 'grid', gridTemplateColumns: '240px minmax(0, 1fr)' },
  sidebar: { background: '#111827', color: '#fff', padding: '28px 18px', minHeight: '100vh' }, brand: { fontSize: 19, fontWeight: 850, padding: '0 10px 24px' }, nav: { display: 'grid', gap: 6 }, navItem: { color: '#AEB7C6', textDecoration: 'none', padding: '11px 12px', borderRadius: 10, fontSize: 14 }, navActive: { color: '#fff', background: '#273244', textDecoration: 'none', padding: '11px 12px', borderRadius: 10, fontSize: 14, fontWeight: 700 },
  content: { padding: '36px', minWidth: 0 }, header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 20, marginBottom: 26 }, headerActions: { display: 'flex', gap: 10, alignItems: 'center' }, eyebrow: { fontSize: 12, letterSpacing: 1.3, fontWeight: 800, color: '#4D63FF' }, h1: { fontSize: 32, lineHeight: 1.15, margin: '5px 0 7px', letterSpacing: '-0.03em' }, subtitle: { color: '#667085', margin: 0, fontSize: 15 }, primaryButton: { border: 0, borderRadius: 12, background: '#111827', color: '#fff', padding: '12px 17px', fontWeight: 750, cursor: 'pointer', textDecoration: 'none' }, ghostButton: { border: '1px solid #D7DCE4', background: '#fff', borderRadius: 10, padding: '10px 13px', color: '#344054', fontWeight: 700, cursor: 'pointer' }, metricGrid: { display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 14, marginBottom: 16 }, metricCard: { background: '#fff', borderRadius: 16, padding: 18, border: '1px solid #E8ECF2' }, metricLabel: { color: '#667085', fontSize: 13, fontWeight: 650 }, metricValue: { fontSize: 30, fontWeight: 850, marginTop: 8, letterSpacing: '-0.03em' }, metricSub: { color: '#98A2B3', fontSize: 12, marginTop: 5 }, twoCol: { display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: 16, marginBottom: 16 }, panel: { background: '#fff', borderRadius: 16, padding: 20, border: '1px solid #E8ECF2', minWidth: 0, marginBottom: 16 }, panelHeader: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, marginBottom: 16 }, panelTitle: { fontSize: 17, fontWeight: 800 }, panelSub: { color: '#98A2B3', fontSize: 12, marginTop: 4 }, rows: { display: 'grid', gap: 2, marginTop: 15 }, row: { display: 'flex', justifyContent: 'space-between', gap: 12, padding: '13px 0', borderBottom: '1px solid #F0F2F5', color: '#475467', textDecoration: 'none', fontSize: 14 }, warn: { color: '#B54708' }, actionGrid: { display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 10 }, action: { display: 'grid', gap: 7, padding: 14, background: '#F8FAFC', borderRadius: 12, color: '#344054', textDecoration: 'none' }, disclaimer: { color: '#98A2B3', fontSize: 12, margin: '0 2px' }, notice: { padding: 13, background: '#FFF7ED', border: '1px solid #FED7AA', borderRadius: 12, color: '#9A3412', marginBottom: 16, fontSize: 13 }, error: { padding: 13, background: '#FEF2F2', border: '1px solid #FECACA', borderRadius: 12, color: '#991B1B', marginBottom: 16, fontSize: 13 },
};
