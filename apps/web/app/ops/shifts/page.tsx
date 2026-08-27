'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '../../../lib/supabase';

type ShiftRow = {
  shift_id: string;
  site_id: string;
  site_name: string;
  client_name: string;
  role_id: string;
  role_name: string;
  starts_at: string;
  ends_at: string;
  headcount: number;
  filled_count: number;
  status: 'draft' | 'open' | 'assigned' | 'in_progress' | 'completed' | 'cancelled';
  worker_rate: number | null;
  client_rate: number | null;
  created_at: string;
};

function localDate(value: Date) {
  return value.toLocaleDateString('en-CA');
}

function formatShiftTime(startsAt: string, endsAt: string) {
  const start = new Date(startsAt);
  const end = new Date(endsAt);
  const date = start.toLocaleDateString('en-SG', { day: 'numeric', month: 'short', year: 'numeric' });
  const time = `${start.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit', hour12: false })}–${end.toLocaleTimeString('en-SG', { hour: '2-digit', minute: '2-digit', hour12: false })}`;
  return `${date} · ${time}`;
}

export default function ShiftsPage() {
  const [rows, setRows] = useState<ShiftRow[]>([]);
  const [from, setFrom] = useState(() => localDate(new Date()));
  const [to, setTo] = useState(() => {
    const date = new Date();
    date.setDate(date.getDate() + 30);
    return localDate(date);
  });
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');

  const totals = useMemo(() => ({
    shifts: rows.length,
    required: rows.reduce((sum, row) => sum + Number(row.headcount), 0),
    filled: rows.reduce((sum, row) => sum + Number(row.filled_count), 0),
    gaps: rows.reduce((sum, row) => sum + Math.max(Number(row.headcount) - Number(row.filled_count), 0), 0),
  }), [rows]);

  async function loadQueue() {
    if (!supabase) {
      setRows([]);
      setMessage('Live shift operations are not configured in this deployment. Set the Supabase public environment variables for staging.');
      setLoading(false);
      return;
    }

    const fromAt = new Date(`${from}T00:00:00`);
    const toAt = new Date(`${to}T00:00:00`);
    if (!from || !to || Number.isNaN(fromAt.getTime()) || Number.isNaN(toAt.getTime()) || toAt <= fromAt) {
      setRows([]);
      setMessage('Choose an end date after the start date.');
      setLoading(false);
      return;
    }

    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_ops_shift_queue', {
      p_from: fromAt.toISOString(),
      p_to: toAt.toISOString(),
    });
    if (error) {
      setRows([]);
      setMessage(error.message.includes('authentication required') || error.message.includes('authorised')
        ? 'Sign in with an authorised Ops account to view the live shift queue.'
        : 'Unable to load the shift queue. Please refresh and try again.');
    } else {
      setRows((data ?? []) as ShiftRow[]);
    }
    setLoading(false);
  }

  useEffect(() => { void loadQueue(); }, []);

  return (
    <section style={styles.page}>
      <header style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS / SHIFTS</div>
          <h1 style={styles.h1}>Shift coverage</h1>
          <p style={styles.sub}>Monitor demand and aggregate fill without exposing worker identities.</p>
        </div>
        <div style={styles.headerActions}>
          <Link href="/ops/login" style={styles.secondaryButton}>Staff sign in</Link>
          <Link href="/ops" style={styles.secondaryButton}>Back to overview</Link>
        </div>
      </header>

      <section style={styles.filters} aria-label="Shift queue date range">
        <label style={styles.label}>From<input style={styles.input} type="date" value={from} onChange={(event) => setFrom(event.target.value)} /></label>
        <label style={styles.label}>To<input style={styles.input} type="date" value={to} onChange={(event) => setTo(event.target.value)} /></label>
        <button style={styles.primaryButton} onClick={() => void loadQueue()} disabled={loading}>{loading ? 'Loading…' : 'Refresh queue'}</button>
      </section>

      <section style={styles.summary} aria-label="Shift coverage summary">
        <div style={styles.summaryItem}><strong>{totals.shifts}</strong><span> shifts</span></div>
        <div style={styles.summaryItem}><strong>{totals.filled}/{totals.required}</strong><span> positions filled</span></div>
        <div style={styles.summaryItem}><strong>{totals.gaps}</strong><span> open gaps</span></div>
      </section>

      {message && <p style={styles.message} role="alert">{message}</p>}

      <section style={styles.panel}>
        {loading ? <p style={styles.empty}>Loading authorised shift queue…</p> : rows.length === 0 ? (
          <p style={styles.empty}>No shifts are visible for this period.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={styles.table}>
              <thead><tr><th style={styles.th}>Shift</th><th style={styles.th}>Client & site</th><th style={styles.th}>Coverage</th><th style={styles.th}>Status</th><th style={styles.th}>Rates</th></tr></thead>
              <tbody>{rows.map((row) => {
                const gaps = Math.max(Number(row.headcount) - Number(row.filled_count), 0);
                return <tr key={row.shift_id}>
                  <td style={styles.strong}><div>{row.role_name}</div><div style={styles.muted}>{formatShiftTime(row.starts_at, row.ends_at)}</div></td>
                  <td style={styles.td}><div>{row.client_name}</div><div style={styles.muted}>{row.site_name}</div></td>
                  <td style={styles.td}><strong>{row.filled_count}/{row.headcount}</strong><div><span style={gaps === 0 ? styles.ok : styles.warn}>{gaps === 0 ? 'Covered' : `${gaps} gap${gaps === 1 ? '' : 's'}`}</span></div></td>
                  <td style={styles.td}><span style={styles.status}>{row.status.replaceAll('_', ' ')}</span></td>
                  <td style={styles.td}>{row.worker_rate == null || row.client_rate == null ? 'Not set' : <><div>Worker S${Number(row.worker_rate).toFixed(2)}/hr</div><div style={styles.muted}>Client S${Number(row.client_rate).toFixed(2)}/hr</div></>}</td>
                </tr>;
              })}</tbody>
            </table>
          </div>
        )}
      </section>

      <p style={styles.note}><strong>Access control:</strong> this view is generated only by the Ops-authorised server RPC. It returns shift demand and aggregate active assignments only; worker, attendance, and identity records remain protected by their own RLS boundaries.</p>
    </section>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', padding: 36, background: '#F5F7FB', color: '#101828' },
  header: { maxWidth: 1180, margin: '0 auto 22px', display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', flexWrap: 'wrap' }, headerActions: { display: 'flex', gap: 8, flexWrap: 'wrap' },
  eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 }, h1: { fontSize: 34, margin: '5px 0 6px', letterSpacing: '-0.03em' }, sub: { margin: 0, color: '#667085' },
  filters: { maxWidth: 1140, margin: '0 auto 16px', display: 'flex', gap: 12, alignItems: 'end', flexWrap: 'wrap' }, label: { display: 'grid', gap: 6, color: '#475467', fontSize: 13, fontWeight: 700 }, input: { border: '1px solid #D0D5DD', borderRadius: 9, padding: '10px 11px', background: '#fff', color: '#101828' },
  primaryButton: { border: 0, borderRadius: 10, padding: '11px 14px', background: '#111827', color: '#fff', fontWeight: 700, cursor: 'pointer', minHeight: 40 }, secondaryButton: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #D0D5DD', padding: '10px 13px', borderRadius: 10, background: '#fff' },
  summary: { maxWidth: 1180, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12 }, summaryItem: { padding: '14px 16px', background: '#fff', border: '1px solid #E8ECF2', borderRadius: 12, color: '#667085', fontSize: 13 },
  message: { maxWidth: 1140, margin: '0 auto 14px', padding: '12px 16px', background: '#FFF7ED', border: '1px solid #FED7AA', borderRadius: 12, color: '#9A3412', fontSize: 13 }, panel: { maxWidth: 1180, margin: '0 auto', background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16, padding: 20 }, empty: { color: '#667085', textAlign: 'center', padding: 28 },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#98A2B3', padding: '10px 8px', borderBottom: '1px solid #EAECF0' }, td: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467', verticalAlign: 'top' }, strong: { fontWeight: 750, color: '#101828' }, muted: { color: '#98A2B3', fontSize: 12, marginTop: 4 },
  ok: { display: 'inline-block', marginTop: 7, padding: '4px 8px', borderRadius: 999, background: '#ECFDF3', color: '#027A48', fontSize: 11, fontWeight: 700 }, warn: { display: 'inline-block', marginTop: 7, padding: '4px 8px', borderRadius: 999, background: '#FFF7ED', color: '#C2410C', fontSize: 11, fontWeight: 700 }, status: { display: 'inline-block', borderRadius: 999, padding: '4px 8px', background: '#F2F4F7', color: '#475467', fontSize: 11, fontWeight: 700, textTransform: 'capitalize' },
  note: { maxWidth: 1140, margin: '14px auto 0', padding: '14px 18px', color: '#667085', fontSize: 12, lineHeight: 1.5 },
};
