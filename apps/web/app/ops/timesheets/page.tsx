'use client';

import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type QueueRow = {
  timesheet_id: string;
  worker_label: string;
  site_name: string;
  role_name: string;
  starts_at: string;
  ends_at: string;
  payable_minutes: number;
  exception_label: string;
  submitted_at: string;
};

export default function TimesheetQueue() {
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [busyId, setBusyId] = useState<string | null>(null);

  const counts = useMemo(() => ({
    pending: rows.length,
    clean: rows.filter((r) => r.exception_label === 'Clean').length,
    review: rows.filter((r) => r.exception_label !== 'Clean').length,
  }), [rows]);

  async function loadQueue() {
    if (!supabase) {
      setMessage('Live Ops actions are not configured yet. Set the Supabase public environment variables for staging.');
      setLoading(false);
      return;
    }
    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_timesheet_review_queue');
    if (error) {
      setMessage(error.message.includes('JWT') || error.message.includes('authorised')
        ? 'Sign in with an authorised supervisor or Ops account to view the live queue.'
        : `Unable to load queue: ${error.message}`);
      setRows([]);
    } else {
      setRows((data ?? []) as QueueRow[]);
    }
    setLoading(false);
  }

  useEffect(() => { void loadQueue(); }, []);

  async function review(id: string, decision: 'approve' | 'reject') {
    if (!supabase || busyId) return;
    let reason: string | null = null;
    if (decision === 'reject') {
      reason = window.prompt('Reason for rejection (required; max 500 characters):')?.trim() || null;
      if (!reason) return;
    }

    setBusyId(id);
    setMessage('');
    const { error } = await supabase.rpc('review_timesheet', {
      p_timesheet_id: id,
      p_decision: decision,
      p_rejection_reason: reason,
    });
    if (error) {
      setMessage(`Action failed: ${error.message}`);
    } else {
      setRows((current) => current.filter((r) => r.timesheet_id !== id));
      setMessage(decision === 'approve' ? 'Timesheet approved and audit event recorded.' : 'Timesheet rejected and returned for correction.');
    }
    setBusyId(null);
  }

  return (
    <section style={styles.page} aria-labelledby="timesheets-title">
      <header style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS / TIMESHEETS</div>
          <h1 id="timesheets-title" style={styles.h1}>Approval queue</h1>
          <p style={styles.sub}>Approve clean attendance, investigate exceptions, and prepare payroll-ready records.</p>
        </div>
        <div style={styles.headerActions}>
          <a href="/ops/login" style={styles.back}>Staff sign in</a>
          <a href="/ops" style={styles.back}>Back to overview</a>
        </div>
      </header>

      <section style={styles.summary} aria-label="Timesheet queue summary">
        <div><strong>{counts.pending}</strong><span> pending</span></div>
        <div><strong>{counts.clean}</strong><span> clean matches</span></div>
        <div><strong>{counts.review}</strong><span> need review</span></div>
      </section>

      {message && <section aria-live="polite" style={styles.message}>{message}</section>}

      <section style={styles.panel}>
        {loading ? <p style={styles.empty}>Loading authorised queue…</p> : rows.length === 0 ? (
          <p style={styles.empty}>No submitted timesheets are currently visible to this account.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={styles.table}>
              <thead><tr><th scope="col" style={styles.th}>Worker</th><th scope="col" style={styles.th}>Site</th><th scope="col" style={styles.th}>Shift</th><th scope="col" style={styles.th}>Payable</th><th scope="col" style={styles.th}>Exception</th><th scope="col" style={styles.th}>Action</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.timesheet_id}>
                    <td style={styles.strong}>{r.worker_label}</td>
                    <td style={styles.td}>{r.site_name}</td>
                    <td style={styles.td}>{r.role_name} · {new Date(r.starts_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}–{new Date(r.ends_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</td>
                    <td style={styles.td}>{Math.floor(r.payable_minutes / 60)}h {r.payable_minutes % 60}m</td>
                    <td style={styles.td}><span style={r.exception_label === 'Clean' ? styles.ok : styles.warn}>{r.exception_label}</span></td>
                    <td style={styles.td}>
                      <div style={styles.actions}>
                        <button disabled={busyId === r.timesheet_id} onClick={() => void review(r.timesheet_id, 'approve')} style={styles.approve}>Approve</button>
                        <button disabled={busyId === r.timesheet_id} onClick={() => void review(r.timesheet_id, 'reject')} style={styles.reject}>Reject</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section style={styles.note}>
        <strong>Security:</strong> the queue is generated server-side, worker identifiers are masked, supervisors only receive assigned-site records, approval/rejection is enforced again inside the review RPC, and every decision writes an audit event.
      </section>
    </section>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#F5F7FB', padding: 36 },
  header: { maxWidth: 1180, margin: '0 auto 22px', display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', flexWrap: 'wrap' },
  headerActions: { display: 'flex', gap: 8, flexWrap: 'wrap' },
  eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 },
  h1: { fontSize: 34, margin: '5px 0 6px', letterSpacing: '-0.03em' },
  sub: { margin: 0, color: '#667085' },
  back: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #D0D5DD', padding: '10px 13px', borderRadius: 10, background: '#fff' },
  summary: { maxWidth: 1180, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12, fontSize: 14, color: '#667085' },
  message: { maxWidth: 1140, margin: '0 auto 14px', padding: '12px 16px', background: '#EEF2FF', border: '1px solid #C7D2FE', borderRadius: 12, color: '#3730A3', fontSize: 13 },
  panel: { maxWidth: 1180, margin: '0 auto', background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16, padding: 20 },
  empty: { color: '#667085', textAlign: 'center', padding: 28 },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#98A2B3', padding: '10px 8px', borderBottom: '1px solid #EAECF0' },
  td: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467' }, strong: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', fontWeight: 750 },
  ok: { color: '#027A48', background: '#ECFDF3', borderRadius: 999, padding: '5px 8px', fontWeight: 700 }, warn: { color: '#B54708', background: '#FFFAEB', borderRadius: 999, padding: '5px 8px', fontWeight: 700 },
  actions: { display: 'flex', gap: 7 }, approve: { border: 0, background: '#111827', color: '#fff', padding: '8px 10px', borderRadius: 8, fontWeight: 700, cursor: 'pointer' }, reject: { border: '1px solid #D0D5DD', background: '#fff', color: '#B42318', padding: '8px 10px', borderRadius: 8, fontWeight: 700, cursor: 'pointer' },
  note: { maxWidth: 1140, margin: '14px auto 0', padding: '14px 18px', color: '#667085', fontSize: 12, lineHeight: 1.5 },
};
