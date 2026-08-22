'use client';

import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type ReviewRow = {
  worker_id: string;
  worker_alias: string;
  worker_status: string;
  identity_verified: boolean;
  residency_verified: boolean;
  work_eligibility: string;
  approved_roles: number;
  pending_roles: number;
  outstanding_training: number;
  open_vetting: number;
  deployable_now: boolean;
  updated_at: string;
};

const stagingRows: ReviewRow[] = [
  { worker_id: 'staging-a', worker_alias: 'W-A13F9C21', worker_status: 'deployable', identity_verified: true, residency_verified: true, work_eligibility: 'eligible', approved_roles: 2, pending_roles: 0, outstanding_training: 0, open_vetting: 0, deployable_now: true, updated_at: '2026-08-22T12:55:00Z' },
  { worker_id: 'staging-b', worker_alias: 'W-B72D41E8', worker_status: 'review', identity_verified: true, residency_verified: true, work_eligibility: 'eligible', approved_roles: 0, pending_roles: 1, outstanding_training: 1, open_vetting: 1, deployable_now: false, updated_at: '2026-08-22T12:25:00Z' },
  { worker_id: 'staging-c', worker_alias: 'W-C05E88AA', worker_status: 'review', identity_verified: false, residency_verified: false, work_eligibility: 'pending', approved_roles: 1, pending_roles: 0, outstanding_training: 0, open_vetting: 0, deployable_now: false, updated_at: '2026-08-22T11:50:00Z' },
];

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('en-SG', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Singapore' }).format(date);
}

function readinessLabel(row: ReviewRow) {
  if (row.deployable_now) return 'Deployable';
  if (row.worker_status === 'suspended' || row.worker_status === 'rejected') return 'Blocked';
  return 'Review';
}

function tone(label: string) {
  if (label === 'Deployable') return { background: '#ECFDF3', color: '#027A48' };
  if (label === 'Review') return { background: '#FFFAEB', color: '#B54708' };
  return { background: '#FEF3F2', color: '#B42318' };
}

export default function WorkersPage() {
  const [rows, setRows] = useState<ReviewRow[]>([]);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<'All' | 'Deployable' | 'Review' | 'Blocked'>('All');
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [mode, setMode] = useState<'live' | 'staging'>('staging');

  async function loadQueue() {
    setLoading(true);
    setMessage('');
    if (!supabase) {
      setRows(stagingRows);
      setMode('staging');
      setMessage('Showing staging examples because Supabase public staging variables are not configured in this build.');
      setLoading(false);
      return;
    }
    const { data: session } = await supabase.auth.getSession();
    if (!session.session) {
      window.location.assign('/ops/login');
      return;
    }
    const { data, error } = await supabase.rpc('get_worker_review_queue', { p_limit: 200 });
    if (error) {
      setRows([]);
      setMode('live');
      setMessage('Unable to load the authorised worker review queue. Check access and try again.');
    } else {
      setRows((data ?? []) as ReviewRow[]);
      setMode('live');
    }
    setLoading(false);
  }

  useEffect(() => { void loadQueue(); }, []);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((row) => {
      const label = readinessLabel(row);
      const matchesStatus = status === 'All' || label === status;
      const searchable = [row.worker_alias, row.worker_status, row.work_eligibility, label].join(' ').toLowerCase();
      return matchesStatus && (!q || searchable.includes(q));
    });
  }, [rows, query, status]);

  const deployable = rows.filter((row) => row.deployable_now).length;
  const attention = rows.length - deployable;
  const trainingIssues = rows.filter((row) => row.outstanding_training > 0).length;

  return (
    <section style={{ padding: 'clamp(20px,4vw,36px)', background: '#F5F7FB', minHeight: '100vh', color: '#101828' }}>
      <div style={{ maxWidth: 1180, margin: '0 auto' }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <div>
            <p style={{ margin: '0 0 6px', color: '#4D63FF', fontSize: 12, fontWeight: 800, letterSpacing: 1 }}>OPS · WORKERS</p>
            <h1 style={{ margin: 0, fontSize: 'clamp(30px,4vw,44px)' }}>Worker readiness review</h1>
            <p style={{ margin: '10px 0 0', color: '#667085', lineHeight: 1.6, maxWidth: 760 }}>
              Review live deployability signals through a pseudonymous, server-authorised queue. Identity, eligibility, vetting and training decisions remain backend-authoritative.
            </p>
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
            <span style={{ background: mode === 'live' ? '#ECFDF3' : '#EEF2FF', color: mode === 'live' ? '#027A48' : '#344054', borderRadius: 999, padding: '9px 12px', fontSize: 12, fontWeight: 800 }}>{mode === 'live' ? 'LIVE AUTHORISED DATA' : 'STAGING-SAFE VIEW'}</span>
            <button type="button" onClick={() => void loadQueue()} disabled={loading} style={secondaryButton}>{loading ? 'Refreshing…' : 'Refresh'}</button>
          </div>
        </div>

        {message && <p role="status" style={{ margin: '16px 0 0', background: '#FFF7ED', color: '#9A3412', border: '1px solid #FED7AA', borderRadius: 10, padding: 12 }}>{message}</p>}

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(170px,1fr))', gap: 12, marginTop: 28 }}>
          <Metric label="Workers in queue" value={rows.length} />
          <Metric label="Deployable now" value={deployable} />
          <Metric label="Needs attention" value={attention} />
          <Metric label="Training gaps" value={trainingIssues} />
        </div>

        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginTop: 24, alignItems: 'end' }}>
          <label style={labelStyle}>Search queue
            <input value={query} onChange={(event) => setQuery(event.target.value.slice(0, 80))} placeholder="Worker alias or status" aria-label="Search worker review queue" style={input} />
          </label>
          <label style={{ ...labelStyle, flex: '0 1 200px', minWidth: 180 }}>Readiness
            <select value={status} onChange={(event) => setStatus(event.target.value as typeof status)} style={input}>
              <option>All</option><option>Deployable</option><option>Review</option><option>Blocked</option>
            </select>
          </label>
        </div>

        <div style={{ overflowX: 'auto', marginTop: 18, borderRadius: 14, border: '1px solid #E8ECF2', background: '#fff' }}>
          <table style={table}>
            <thead><tr><th style={th}>Worker</th><th style={th}>Readiness</th><th style={th}>Identity / residency</th><th style={th}>Eligibility</th><th style={th}>Roles</th><th style={th}>Training gaps</th><th style={th}>Open vetting</th><th style={th}>Updated</th></tr></thead>
            <tbody>
              {visible.map((row) => {
                const label = readinessLabel(row);
                return <tr key={row.worker_id}>
                  <td style={tdStrong}>{row.worker_alias}</td>
                  <td style={td}><span style={{ ...pill, ...tone(label) }}>{label}</span></td>
                  <td style={td}>{row.identity_verified ? 'ID ✓' : 'ID pending'} · {row.residency_verified ? 'Residency ✓' : 'Residency pending'}</td>
                  <td style={td}>{row.work_eligibility}</td>
                  <td style={td}>{row.approved_roles} approved · {row.pending_roles} pending</td>
                  <td style={td}>{row.outstanding_training}</td>
                  <td style={td}>{row.open_vetting}</td>
                  <td style={td}>{formatDateTime(row.updated_at)}</td>
                </tr>;
              })}
              {!loading && visible.length === 0 && <tr><td colSpan={8} style={{ ...td, textAlign: 'center', padding: 30 }}>No workers match this filter.</td></tr>}
            </tbody>
          </table>
        </div>

        <div style={{ marginTop: 18, display: 'grid', gap: 8, background: '#fff', border: '1px solid #E4E7EC', borderRadius: 14, padding: 16 }}>
          <strong style={{ fontSize: 14 }}>Privacy & control boundary</strong>
          <p style={{ margin: 0, color: '#667085', lineHeight: 1.55, fontSize: 13 }}>The queue uses worker aliases and operational readiness signals only. Names, phone numbers, national identifiers, raw identity payloads and bank details are not returned by this RPC. Review mutations remain separate audited server-side actions.</p>
        </div>
      </div>
    </section>
  );
}

function Metric({ label, value }: { label: string; value: number }) { return <div style={{ background: '#fff', border: '1px solid #E4E7EC', borderRadius: 14, padding: 16 }}><div style={{ color: '#667085', fontSize: 12, fontWeight: 700 }}>{label}</div><div style={{ marginTop: 6, fontSize: 28, fontWeight: 850 }}>{value}</div></div>; }

const table = { width: '100%', borderCollapse: 'collapse' as const, minWidth: 1080 };
const th = { textAlign: 'left' as const, padding: 12, color: '#667085', borderBottom: '1px solid #EAECF0', fontSize: 12, whiteSpace: 'nowrap' as const };
const td = { padding: 14, borderBottom: '1px solid #F0F2F5', color: '#475467', fontSize: 13, verticalAlign: 'middle' as const };
const tdStrong = { ...td, color: '#101828', fontWeight: 750, whiteSpace: 'nowrap' as const };
const labelStyle = { display: 'grid', gap: 6, minWidth: 240, flex: '1 1 320px', color: '#344054', fontSize: 13, fontWeight: 700 } as const;
const input = { minHeight: 44, border: '1px solid #D0D5DD', borderRadius: 10, padding: '10px 12px', background: '#fff', color: '#101828', fontSize: 16, boxSizing: 'border-box' as const, width: '100%' };
const pill = { display: 'inline-block', borderRadius: 999, padding: '5px 9px', fontWeight: 800, fontSize: 12, whiteSpace: 'nowrap' as const };
const secondaryButton = { minHeight: 44, border: '1px solid #D0D5DD', borderRadius: 10, padding: '10px 14px', background: '#fff', color: '#344054', fontWeight: 800, cursor: 'pointer' };
