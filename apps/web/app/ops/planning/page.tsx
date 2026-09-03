'use client';

import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { safeOpsError } from '../../../lib/ops';

type SlaRow = {
  client_id: string;
  client_name: string;
  site_id: string;
  site_name: string;
  target_fulfilment_pct: number;
  required_headcount: number;
  filled_headcount: number;
  fulfilment_pct: number;
  cancellations: number;
  no_shows: number;
  shifts_count: number;
  sla_status: 'meeting' | 'watch' | 'breach_risk';
};

type ForecastRow = {
  forecast_date: string;
  client_id: string;
  client_name: string;
  site_id: string;
  site_name: string;
  role_id: string;
  role_name: string;
  projected_headcount: number;
  historical_occurrences: number;
  confidence: 'high' | 'medium' | 'low';
};

const demoSla: SlaRow[] = [
  { client_id: 'demo-1', client_name: 'Harbour Hotel Group', site_id: 'demo-s1', site_name: 'Marina Bay', target_fulfilment_pct: 85, required_headcount: 148, filled_headcount: 139, fulfilment_pct: 93.92, cancellations: 4, no_shows: 2, shifts_count: 18, sla_status: 'meeting' },
  { client_id: 'demo-2', client_name: 'Lifestyle Retailer', site_id: 'demo-s2', site_name: 'Orchard', target_fulfilment_pct: 90, required_headcount: 96, filled_headcount: 84, fulfilment_pct: 87.5, cancellations: 5, no_shows: 3, shifts_count: 12, sla_status: 'watch' },
  { client_id: 'demo-3', client_name: 'Convention Venue', site_id: 'demo-s3', site_name: 'Expo', target_fulfilment_pct: 90, required_headcount: 130, filled_headcount: 105, fulfilment_pct: 80.77, cancellations: 7, no_shows: 4, shifts_count: 9, sla_status: 'breach_risk' },
];

const demoForecast: ForecastRow[] = [
  { forecast_date: '2026-09-02', client_id: 'demo-1', client_name: 'Harbour Hotel Group', site_id: 'demo-s1', site_name: 'Marina Bay', role_id: 'r1', role_name: 'Banquet Crew', projected_headcount: 28, historical_occurrences: 8, confidence: 'high' },
  { forecast_date: '2026-09-03', client_id: 'demo-3', client_name: 'Convention Venue', site_id: 'demo-s3', site_name: 'Expo', role_id: 'r2', role_name: 'Event Crew', projected_headcount: 42, historical_occurrences: 6, confidence: 'high' },
  { forecast_date: '2026-09-04', client_id: 'demo-2', client_name: 'Lifestyle Retailer', site_id: 'demo-s2', site_name: 'Orchard', role_id: 'r3', role_name: 'Promoter', projected_headcount: 16, historical_occurrences: 4, confidence: 'medium' },
];

export default function PlanningPage() {
  const [sla, setSla] = useState<SlaRow[]>([]);
  const [forecast, setForecast] = useState<ForecastRow[]>([]);
  const [loading, setLoading] = useState(Boolean(supabase));
  const [message, setMessage] = useState('');

  useEffect(() => {
    let active = true;
    async function load() {
      if (!supabase) return;
      setLoading(true);
      const [slaResult, forecastResult] = await Promise.all([
        supabase.rpc('get_client_sla_dashboard', { p_days: 30, p_client_id: null }),
        supabase.rpc('get_ops_demand_forecast', { p_forecast_days: 14, p_history_weeks: 8, p_client_id: null }),
      ]);
      if (!active) return;
      if (slaResult.error || forecastResult.error) {
        setMessage(safeOpsError(slaResult.error || forecastResult.error, 'Unable to load planning data. No operational records were changed.'));
      } else {
        setSla((slaResult.data ?? []) as SlaRow[]);
        setForecast((forecastResult.data ?? []) as ForecastRow[]);
      }
      setLoading(false);
    }
    void load();
    return () => { active = false; };
  }, []);

  const slaRows = supabase ? sla : demoSla;
  const forecastRows = supabase ? forecast : demoForecast;
  const summary = useMemo(() => {
    const totalRequired = slaRows.reduce((sum, row) => sum + Number(row.required_headcount || 0), 0);
    const totalFilled = slaRows.reduce((sum, row) => sum + Number(row.filled_headcount || 0), 0);
    const fill = totalRequired ? (100 * totalFilled / totalRequired) : 100;
    return {
      fill,
      breach: slaRows.filter((row) => row.sla_status === 'breach_risk').length,
      watch: slaRows.filter((row) => row.sla_status === 'watch').length,
      forecastHeadcount: forecastRows.reduce((sum, row) => sum + Number(row.projected_headcount || 0), 0),
    };
  }, [slaRows, forecastRows]);

  return (
    <section style={styles.page}>
      <div style={styles.wrap}>
        <div style={styles.eyebrow}>PLANNING & SLA</div>
        <div style={styles.header}>
          <div>
            <h1 style={styles.h1}>Demand & fulfilment cockpit</h1>
            <p style={styles.subtitle}>Decision support from historical shifts and audited assignment outcomes. No automatic staffing, pricing or client promises.</p>
          </div>
        </div>

        {!supabase && <div style={styles.notice}>Staging Supabase is not configured in this deployment. Showing clearly labelled demonstration data only.</div>}
        {message && <div style={styles.error}>{message}</div>}

        <div style={styles.metrics}>
          <Metric label="30-day fill" value={`${summary.fill.toFixed(1)}%`} sub="Across visible sites" />
          <Metric label="SLA breach risk" value={String(summary.breach)} sub="Sites below watch band" />
          <Metric label="SLA watch" value={String(summary.watch)} sub="Within 5 pts of target" />
          <Metric label="14-day projected demand" value={String(summary.forecastHeadcount)} sub="Forecast headcount units" />
        </div>

        <section style={styles.panel}>
          <div style={styles.panelHeader}><div><h2 style={styles.h2}>Client SLA performance</h2><p style={styles.panelSub}>Required vs filled headcount, cancellations and no-shows over the last 30 days.</p></div></div>
          {loading ? <p style={styles.muted}>Loading SLA data…</p> : <div style={styles.tableWrap}><table style={styles.table}>
            <thead><tr>{['Client / site','Target','Required','Filled','Fill','Cancellations','No-shows','Status'].map((label) => <th key={label} style={styles.th}>{label}</th>)}</tr></thead>
            <tbody>{slaRows.map((row) => <tr key={`${row.client_id}-${row.site_id}`}>
              <td style={styles.td}><strong>{row.client_name}</strong><div style={styles.small}>{row.site_name}</div></td>
              <td style={styles.td}>{Number(row.target_fulfilment_pct).toFixed(0)}%</td>
              <td style={styles.td}>{row.required_headcount}</td>
              <td style={styles.td}>{row.filled_headcount}</td>
              <td style={styles.tdStrong}>{Number(row.fulfilment_pct).toFixed(1)}%</td>
              <td style={styles.td}>{row.cancellations}</td>
              <td style={styles.td}>{row.no_shows}</td>
              <td style={styles.td}><Status value={row.sla_status} /></td>
            </tr>)}</tbody>
          </table></div>}
        </section>

        <section style={styles.panel}>
          <div style={styles.panelHeader}><div><h2 style={styles.h2}>14-day demand forecast</h2><p style={styles.panelSub}>Projected role demand from recurring historical shift patterns. Confidence reflects recurrence depth, not certainty.</p></div></div>
          {loading ? <p style={styles.muted}>Loading forecast…</p> : <div style={styles.tableWrap}><table style={styles.table}>
            <thead><tr>{['Date','Client / site','Role','Projected','Occurrences','Confidence'].map((label) => <th key={label} style={styles.th}>{label}</th>)}</tr></thead>
            <tbody>{forecastRows.slice(0, 50).map((row) => <tr key={`${row.forecast_date}-${row.site_id}-${row.role_id}`}>
              <td style={styles.td}>{row.forecast_date}</td>
              <td style={styles.td}><strong>{row.client_name}</strong><div style={styles.small}>{row.site_name}</div></td>
              <td style={styles.td}>{row.role_name}</td>
              <td style={styles.tdStrong}>{row.projected_headcount}</td>
              <td style={styles.td}>{row.historical_occurrences}</td>
              <td style={styles.td}>{row.confidence}</td>
            </tr>)}</tbody>
          </table></div>}
          <p style={styles.footnote}>Forecast output is advisory only. Ops must still confirm each labour requirement and assignment through existing approval controls.</p>
        </section>
      </div>
    </section>
  );
}

function Metric({ label, value, sub }: { label: string; value: string; sub: string }) {
  return <article style={styles.metric}><div style={styles.metricLabel}>{label}</div><div style={styles.metricValue}>{value}</div><div style={styles.small}>{sub}</div></article>;
}

function Status({ value }: { value: SlaRow['sla_status'] }) {
  const label = value === 'breach_risk' ? 'Breach risk' : value === 'watch' ? 'Watch' : 'Meeting';
  return <span style={{ ...styles.badge, borderColor: value === 'meeting' ? '#b7ebc6' : value === 'watch' ? '#f6d48a' : '#f1a7a7' }}>{label}</span>;
}

const styles = {
  page: { minHeight: '100vh', background: '#f5f7fb', color: '#101828', padding: '36px 22px 64px' },
  wrap: { maxWidth: 1280, margin: '0 auto' },
  eyebrow: { fontSize: 12, fontWeight: 800, letterSpacing: 1.2, color: '#667085' },
  header: { display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'flex-start', marginBottom: 24 },
  h1: { fontSize: 34, margin: '8px 0' },
  h2: { margin: 0, fontSize: 20 },
  subtitle: { color: '#667085', maxWidth: 760, lineHeight: 1.55, margin: 0 },
  notice: { background: '#fff7ed', border: '1px solid #fed7aa', padding: 14, borderRadius: 12, marginBottom: 18 },
  error: { background: '#fef2f2', border: '1px solid #fecaca', padding: 14, borderRadius: 12, marginBottom: 18 },
  metrics: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(190px,1fr))', gap: 14, marginBottom: 22 },
  metric: { background: '#fff', border: '1px solid #e4e7ec', borderRadius: 16, padding: 18 },
  metricLabel: { color: '#667085', fontSize: 13 },
  metricValue: { fontSize: 30, fontWeight: 800, margin: '8px 0 4px' },
  panel: { background: '#fff', border: '1px solid #e4e7ec', borderRadius: 18, padding: 20, marginTop: 18 },
  panelHeader: { display: 'flex', justifyContent: 'space-between', gap: 16, marginBottom: 16 },
  panelSub: { color: '#667085', margin: '6px 0 0', fontSize: 14 },
  tableWrap: { overflowX: 'auto' as const },
  table: { width: '100%', borderCollapse: 'collapse' as const, minWidth: 860 },
  th: { textAlign: 'left' as const, color: '#667085', fontSize: 12, padding: '10px 9px', borderBottom: '1px solid #eaecf0' },
  td: { padding: '13px 9px', borderBottom: '1px solid #f2f4f7', color: '#475467', fontSize: 13 },
  tdStrong: { padding: '13px 9px', borderBottom: '1px solid #f2f4f7', color: '#101828', fontWeight: 800, fontSize: 13 },
  small: { color: '#98a2b3', fontSize: 12, marginTop: 3 },
  muted: { color: '#667085' },
  badge: { display: 'inline-block', border: '1px solid', borderRadius: 999, padding: '5px 9px', fontSize: 12, fontWeight: 700 },
  footnote: { color: '#98a2b3', fontSize: 12, lineHeight: 1.5, marginBottom: 0 },
} as const;
