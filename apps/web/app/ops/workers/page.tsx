'use client';

import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type WorkerStatus = 'pending' | 'verified' | 'vetted' | 'trained' | 'deployable' | 'suspended' | 'rejected';
type Worker = { worker_id: string; worker_alias: string; worker_status: WorkerStatus; identity_verified: boolean; residency_verified: boolean; work_eligibility: string; approved_roles: number; pending_roles: number; outstanding_training: number; open_vetting: number; deployable_now: boolean; updated_at: string };

const statusLabels: Record<WorkerStatus, string> = { pending: 'Pending', verified: 'Verified', vetted: 'Vetted', trained: 'Trained', deployable: 'Deployable', suspended: 'Suspended', rejected: 'Rejected' };

export default function WorkersPage() {
  const [workers, setWorkers] = useState<Worker[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'needs_review' | 'deployable'>('all');

  const visible = useMemo(() => workers.filter((worker) => filter === 'all' || (filter === 'deployable' ? worker.deployable_now : !worker.deployable_now)), [workers, filter]);

  async function load() {
    if (!supabase) { setLoading(false); setMessage('Live worker review is disabled until the staging Supabase public environment is configured.'); return; }
    setLoading(true); setMessage('');
    const { data, error } = await supabase.rpc('get_worker_review_queue', { p_limit: 100 });
    if (error) { setWorkers([]); setMessage('Sign in with an authorised Ops account to view the pseudonymous worker queue.'); }
    else setWorkers((data ?? []) as Worker[]);
    setLoading(false);
  }

  useEffect(() => { void load(); }, []);

  async function setStatus(worker: Worker, status: WorkerStatus) {
    if (!supabase || busyId) return;
    let reason: string | null = null;
    if (status === 'suspended' || status === 'rejected') {
      reason = window.prompt(`Reason for ${status} (required; do not include identity or health information):`)?.trim() || null;
      if (!reason) return;
    }
    setBusyId(worker.worker_id); setMessage('');
    const { error } = await supabase.rpc('set_worker_operational_status', { p_worker_id: worker.worker_id, p_status: status, p_reason: reason });
    setBusyId(null);
    if (error) { setMessage(`Status not changed: ${error.message}`); return; }
    setMessage(`${worker.worker_alias} updated. The decision and reason-presence were audited.`);
    void load();
  }

  return <section style={styles.page}>
    <header style={styles.header}><div><div style={styles.eyebrow}>OPERATIONS / WORKERS</div><h1 style={styles.h1}>Worker review</h1><p style={styles.sub}>Readiness signals use operational aliases only; detailed identity evidence remains outside this queue.</p></div><div style={styles.filters} aria-label="Worker filter">{(['all', 'needs_review', 'deployable'] as const).map((value) => <button key={value} onClick={() => setFilter(value)} style={filter === value ? styles.filterActive : styles.filter}>{value === 'needs_review' ? 'Needs review' : value[0].toUpperCase() + value.slice(1)}</button>)}</div></header>
    {message && <p aria-live="polite" style={styles.notice}>{message}</p>}
    <section style={styles.panel}>{loading ? <p style={styles.empty}>Loading authorised review queue…</p> : visible.length === 0 ? <p style={styles.empty}>No workers match this filter.</p> : <div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr><th style={styles.th}>Worker</th><th style={styles.th}>Operational status</th><th style={styles.th}>Readiness checks</th><th style={styles.th}>Role / training</th><th style={styles.th}>Action</th></tr></thead><tbody>{visible.map((worker) => <tr key={worker.worker_id}><td style={styles.strong}>{worker.worker_alias}</td><td style={styles.td}><span style={worker.deployable_now ? styles.ok : styles.status}>{statusLabels[worker.worker_status]}</span></td><td style={styles.td}>{worker.identity_verified ? 'Identity verified' : 'Identity pending'} · {worker.residency_verified ? 'residency verified' : 'residency pending'}<br/><span style={styles.muted}>Eligibility: {worker.work_eligibility}</span></td><td style={styles.td}>{worker.approved_roles} approved · {worker.pending_roles} pending<br/><span style={styles.muted}>{worker.outstanding_training} training · {worker.open_vetting} vetting outstanding</span></td><td style={styles.td}><div style={styles.actions}>{!worker.deployable_now && <button disabled={!supabase || busyId === worker.worker_id} onClick={() => void setStatus(worker, 'deployable')} style={styles.approve}>Set deployable</button>}{worker.worker_status !== 'suspended' && <button disabled={!supabase || busyId === worker.worker_id} onClick={() => void setStatus(worker, 'suspended')} style={styles.secondary}>Suspend</button>}</div></td></tr>)}</tbody></table></div>}</section>
    <p style={styles.foot}>Status changes are server-authorised: deployable status is refused until live prerequisites are met, self-review is blocked, and each action creates an audit event.</p>
  </section>;
}

const styles: Record<string, any> = {
  page: { padding: 32, minHeight: '100vh', background: '#f5f7fb', color: '#101828' }, header: { maxWidth: 1180, margin: '0 auto 20px', display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'end', flexWrap: 'wrap' }, eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 }, h1: { fontSize: 32, margin: '5px 0' }, sub: { margin: 0, color: '#667085' }, filters: { display: 'flex', gap: 8, flexWrap: 'wrap' }, filter: { border: '1px solid #D0D5DD', borderRadius: 999, padding: '8px 11px', background: '#fff', color: '#475467', fontWeight: 700, cursor: 'pointer' }, filterActive: { border: '1px solid #111827', borderRadius: 999, padding: '8px 11px', background: '#111827', color: '#fff', fontWeight: 700, cursor: 'pointer' }, notice: { maxWidth: 1140, margin: '0 auto 16px', padding: 13, borderRadius: 10, background: '#EEF2FF', color: '#3730A3', fontSize: 13 }, panel: { maxWidth: 1140, margin: '0 auto', padding: 20, background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16 }, empty: { padding: 25, textAlign: 'center', color: '#667085' }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', padding: '10px 8px', color: '#667085', borderBottom: '1px solid #EAECF0' }, td: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467', verticalAlign: 'top' }, strong: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', fontWeight: 750 }, muted: { color: '#98A2B3', fontSize: 12 }, status: { display: 'inline-block', padding: '4px 8px', borderRadius: 999, background: '#F2F4F7', color: '#475467', fontWeight: 700, fontSize: 12 }, ok: { display: 'inline-block', padding: '4px 8px', borderRadius: 999, background: '#ECFDF3', color: '#027A48', fontWeight: 700, fontSize: 12 }, actions: { display: 'flex', gap: 7, flexWrap: 'wrap' }, approve: { border: 0, borderRadius: 8, background: '#111827', color: '#fff', padding: '8px 10px', fontWeight: 700, cursor: 'pointer' }, secondary: { border: '1px solid #D0D5DD', borderRadius: 8, background: '#fff', color: '#B42318', padding: '8px 10px', fontWeight: 700, cursor: 'pointer' }, foot: { maxWidth: 1140, margin: '14px auto 0', color: '#98A2B3', fontSize: 12, lineHeight: 1.5 },
};
