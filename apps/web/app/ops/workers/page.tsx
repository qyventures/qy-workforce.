'use client';

import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type WorkerStatus = 'pending' | 'verified' | 'vetted' | 'trained' | 'deployable' | 'suspended' | 'rejected';

type WorkerRow = {
  worker_id: string;
  worker_alias: string;
  worker_status: WorkerStatus;
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

function statusLabel(status: WorkerStatus) {
  return status.replaceAll('_', ' ');
}

export default function WorkersPage() {
  const [rows, setRows] = useState<WorkerRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [selected, setSelected] = useState<WorkerRow | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const counts = useMemo(() => ({
    total: rows.length,
    deployable: rows.filter((row) => row.deployable_now).length,
    actionNeeded: rows.filter((row) => !row.deployable_now && !['suspended', 'rejected'].includes(row.worker_status)).length,
  }), [rows]);

  async function loadQueue() {
    if (!supabase) {
      setMessage('Live worker review is not configured yet. Set the Supabase public environment variables for staging.');
      setLoading(false);
      return;
    }
    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_worker_review_queue', { p_limit: 100 });
    if (error) {
      setRows([]);
      setMessage(error.message.includes('JWT') || error.message.includes('authorised')
        ? 'Sign in with an authorised Ops account to view the live worker queue.'
        : 'Unable to load the worker queue. No worker records were changed.');
    } else {
      setRows((data ?? []) as WorkerRow[]);
    }
    setLoading(false);
  }

  useEffect(() => { void loadQueue(); }, []);

  async function applyAdverseStatus(status: 'suspended' | 'rejected') {
    if (!supabase || !selected || busy) return;
    const trimmedReason = reason.trim();
    if (trimmedReason.length < 3 || trimmedReason.length > 500) {
      setMessage('Give a concise operational reason between 3 and 500 characters.');
      return;
    }
    setBusy(true);
    setMessage('');
    const { error } = await supabase.rpc('set_worker_operational_status', {
      p_worker_id: selected.worker_id,
      p_status: status,
      p_reason: trimmedReason,
    });
    setBusy(false);
    if (error) {
      setMessage(error.message.includes('self-review')
        ? 'You cannot change your own worker status.'
        : error.message.includes('authorised') ? 'Your account is not authorised to change worker status.'
          : 'Unable to change this worker status. No status was changed.');
      return;
    }
    setSelected(null);
    setReason('');
    setMessage(`${selected.worker_alias} was marked ${statusLabel(status)}. The server recorded the reason and audit event.`);
    await loadQueue();
  }

  return <main style={styles.page}>
    <header style={styles.header}>
      <div><div style={styles.eyebrow}>OPERATIONS / WORKERS</div><h1 style={styles.h1}>Worker readiness</h1><p style={styles.sub}>Review deployment readiness through a pseudonymous, minimal-data queue.</p></div>
      <div style={styles.headerActions}><a href="/ops/login" style={styles.back}>Staff sign in</a><button style={styles.back} onClick={() => void loadQueue()} disabled={loading}>Refresh</button></div>
    </header>

    <section style={styles.summary}><div><strong>{counts.total}</strong><span> workers</span></div><div><strong>{counts.deployable}</strong><span> deployable now</span></div><div><strong>{counts.actionNeeded}</strong><span> need readiness work</span></div></section>
    {message && <section style={styles.message} role="status">{message}</section>}

    {selected && <section style={styles.dialog} role="dialog" aria-modal="true" aria-labelledby="worker-status-title">
      <h2 id="worker-status-title" style={styles.h2}>Restrict {selected.worker_alias}?</h2>
      <p style={styles.sub}>Use only for an operational decision. Do not enter identity numbers, medical information, or other unnecessary personal data.</p>
      <label style={styles.label}>Reason (3–500 characters)<textarea style={styles.textarea} rows={3} maxLength={500} value={reason} disabled={busy} onChange={(event) => setReason(event.target.value)} placeholder="Operational reason, without sensitive personal data" /></label>
      <div style={styles.actions}><button style={styles.secondary} disabled={busy} onClick={() => { setSelected(null); setReason(''); }}>Cancel</button><button style={styles.suspend} disabled={busy || reason.trim().length < 3} onClick={() => void applyAdverseStatus('suspended')}>{busy ? 'Saving…' : 'Suspend'}</button><button style={styles.reject} disabled={busy || reason.trim().length < 3} onClick={() => void applyAdverseStatus('rejected')}>{busy ? 'Saving…' : 'Reject'}</button></div>
    </section>}

    <section style={styles.panel}>{loading ? <p style={styles.empty}>Loading authorised worker queue…</p> : rows.length === 0 ? <p style={styles.empty}>No worker records are visible to this account.</p> : <div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr><th style={styles.th}>Worker</th><th style={styles.th}>Status</th><th style={styles.th}>Readiness evidence</th><th style={styles.th}>Outstanding work</th><th style={styles.th}>Action</th></tr></thead><tbody>{rows.map((row) => <tr key={row.worker_id}><td style={styles.strong}>{row.worker_alias}</td><td style={styles.td}><span style={row.deployable_now ? styles.ok : styles.warn}>{row.deployable_now ? 'Deployable' : statusLabel(row.worker_status)}</span></td><td style={styles.td}>{row.identity_verified ? 'Identity verified' : 'Identity pending'} · {row.residency_verified ? 'Residency verified' : 'Residency pending'}<br /><span style={styles.muted}>Eligibility: {row.work_eligibility}</span></td><td style={styles.td}>{row.approved_roles} approved role{row.approved_roles === 1 ? '' : 's'} · {row.pending_roles} pending role{row.pending_roles === 1 ? '' : 's'}<br /><span style={styles.muted}>{row.outstanding_training} training · {row.open_vetting} vetting open</span></td><td style={styles.td}>{!['suspended', 'rejected'].includes(row.worker_status) ? <button style={styles.restrict} onClick={() => { setMessage(''); setSelected(row); setReason(''); }}>Restrict</button> : <span style={styles.muted}>Restricted</span>}</td></tr>)}</tbody></table></div>}</section>
    <section style={styles.note}><strong>Security:</strong> names, contacts, identity documents and verification values are not returned to this queue. Deployment eligibility and status changes are rechecked by the authorised database RPC, which prevents self-review and records an audit event.</section>
  </main>;
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#F5F7FB', padding: 36, color: '#101828' }, header: { maxWidth: 1180, margin: '0 auto 22px', display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', flexWrap: 'wrap' }, headerActions: { display: 'flex', gap: 8, flexWrap: 'wrap' }, eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 }, h1: { fontSize: 34, margin: '5px 0 6px', letterSpacing: '-0.03em' }, h2: { margin: '0 0 8px', fontSize: 21 }, sub: { margin: 0, color: '#667085', lineHeight: 1.5 }, back: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #D0D5DD', padding: '10px 13px', borderRadius: 10, background: '#fff', fontSize: 14, cursor: 'pointer' }, summary: { maxWidth: 1180, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12, fontSize: 14, color: '#667085' }, message: { maxWidth: 1140, margin: '0 auto 14px', padding: '12px 16px', background: '#EEF2FF', border: '1px solid #C7D2FE', borderRadius: 12, color: '#3730A3', fontSize: 13 }, dialog: { maxWidth: 760, margin: '0 auto 16px', padding: 20, borderRadius: 16, border: '1px solid #FECACA', background: '#fff' }, label: { display: 'grid', gap: 7, marginTop: 14, fontWeight: 700, fontSize: 13, color: '#344054' }, textarea: { resize: 'vertical', border: '1px solid #D0D5DD', borderRadius: 10, padding: 10, font: 'inherit' }, panel: { maxWidth: 1180, margin: '0 auto', background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16, padding: 20 }, empty: { color: '#667085', textAlign: 'center', padding: 28 }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#98A2B3', padding: '10px 8px', borderBottom: '1px solid #EAECF0' }, td: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467', verticalAlign: 'top' }, strong: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', fontWeight: 750, verticalAlign: 'top' }, muted: { color: '#98A2B3', fontSize: 12 }, ok: { color: '#027A48', background: '#ECFDF3', borderRadius: 999, padding: '5px 8px', fontWeight: 700, textTransform: 'capitalize' }, warn: { color: '#B54708', background: '#FFFAEB', borderRadius: 999, padding: '5px 8px', fontWeight: 700, textTransform: 'capitalize' }, actions: { display: 'flex', gap: 8, marginTop: 16, flexWrap: 'wrap' }, secondary: { border: '1px solid #D0D5DD', background: '#fff', color: '#344054', padding: '9px 12px', borderRadius: 8, fontWeight: 700, cursor: 'pointer' }, suspend: { border: '1px solid #F79009', background: '#FFFAEB', color: '#B54708', padding: '9px 12px', borderRadius: 8, fontWeight: 700, cursor: 'pointer' }, reject: { border: '1px solid #FDA29B', background: '#FEF3F2', color: '#B42318', padding: '9px 12px', borderRadius: 8, fontWeight: 700, cursor: 'pointer' }, restrict: { border: '1px solid #D0D5DD', background: '#fff', color: '#B42318', padding: '8px 10px', borderRadius: 8, fontWeight: 700, cursor: 'pointer' }, note: { maxWidth: 1140, margin: '14px auto 0', padding: '14px 18px', color: '#667085', fontSize: 12, lineHeight: 1.5 },
};
