'use client';

import type { CSSProperties } from 'react';
import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type ReviewRow = {
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

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('en-SG', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Singapore',
  }).format(date);
}

function hours(minutes: number) {
  return `${(Math.max(0, Number(minutes || 0)) / 60).toFixed(2)}h`;
}

const stagingRows: ReviewRow[] = [
  {
    timesheet_id: 'staging-clean',
    worker_label: 'Worker #A13F9C',
    site_name: 'Marina Bay',
    role_name: 'Banquet Service',
    starts_at: '2026-08-22T02:00:00.000Z',
    ends_at: '2026-08-22T10:00:00.000Z',
    payable_minutes: 480,
    exception_label: 'Clean',
    submitted_at: '2026-08-22T10:12:00.000Z',
  },
  {
    timesheet_id: 'staging-geofence',
    worker_label: 'Worker #7B21DD',
    site_name: 'Orchard',
    role_name: 'Retail Assistant',
    starts_at: '2026-08-22T01:00:00.000Z',
    ends_at: '2026-08-22T09:00:00.000Z',
    payable_minutes: 480,
    exception_label: 'Geofence exception',
    submitted_at: '2026-08-22T09:18:00.000Z',
  },
];

export default function ApprovalsPage() {
  const [rows, setRows] = useState<ReviewRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [mode, setMode] = useState<'live' | 'staging'>('staging');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [reason, setReason] = useState('');

  const exceptionCount = useMemo(
    () => rows.filter((row) => row.exception_label !== 'Clean').length,
    [rows],
  );

  async function loadQueue() {
    if (!supabase) {
      setRows(stagingRows);
      setMode('staging');
      setMessage('Showing staging examples because Supabase public staging variables are not configured in this build.');
      setLoading(false);
      return;
    }

    setLoading(true);
    setMessage('');
    const { data, error } = await supabase.rpc('get_timesheet_review_queue');
    if (error) {
      setRows([]);
      setMessage(error.message.includes('authorised') || error.message.includes('JWT')
        ? 'Sign in with an authorised Supervisor, Ops Manager or Admin account to review timesheets.'
        : `Unable to load review queue: ${error.message}`);
    } else {
      setRows((data ?? []) as ReviewRow[]);
      setMode('live');
    }
    setLoading(false);
  }

  useEffect(() => { void loadQueue(); }, []);

  async function review(timesheetId: string, decision: 'approve' | 'reject') {
    if (!supabase || mode === 'staging') {
      setMessage('Staging mode is read-only. Connect the authorised staging Supabase project to perform approval actions.');
      return;
    }

    const rejectionReason = decision === 'reject' ? reason.trim() : null;
    if (decision === 'reject' && !rejectionReason) {
      setMessage('Enter a rejection reason before rejecting this timesheet.');
      return;
    }

    setBusyId(timesheetId);
    setMessage('');
    const { error } = await supabase.rpc('review_timesheet', {
      p_timesheet_id: timesheetId,
      p_decision: decision,
      p_rejection_reason: rejectionReason,
    });

    if (error) {
      setMessage(`Review action failed: ${error.message}`);
    } else {
      setRows((current) => current.filter((row) => row.timesheet_id !== timesheetId));
      setRejectingId(null);
      setReason('');
      setMessage(decision === 'approve' ? 'Timesheet approved and removed from the review queue.' : 'Timesheet rejected and returned for correction.');
    }
    setBusyId(null);
  }

  return (
    <section style={styles.page}>
      <div style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS / SUPERVISOR APPROVALS</div>
          <h1 style={styles.h1}>Timesheet review</h1>
          <p style={styles.sub}>Approve clean submissions quickly and review exceptions without exposing unnecessary worker identity data.</p>
        </div>
        <span style={mode === 'live' ? styles.liveBadge : styles.stagingBadge}>{mode === 'live' ? 'Live authorised queue' : 'Staging preview'}</span>
      </div>

      <div style={styles.cards}>
        <div style={styles.card}><span style={styles.cardLabel}>Awaiting review</span><strong style={styles.cardValue}>{rows.length}</strong></div>
        <div style={styles.card}><span style={styles.cardLabel}>Exceptions</span><strong style={styles.cardValue}>{exceptionCount}</strong></div>
        <div style={styles.card}><span style={styles.cardLabel}>Clean submissions</span><strong style={styles.cardValue}>{Math.max(0, rows.length - exceptionCount)}</strong></div>
      </div>

      <div style={styles.toolbar}>
        <button type="button" onClick={() => void loadQueue()} disabled={loading || busyId !== null} style={styles.secondaryButton}>
          {loading ? 'Refreshing…' : 'Refresh queue'}
        </button>
      </div>

      {message && <div role="status" aria-live="polite" style={styles.message}>{message}</div>}

      <div style={styles.panel}>
        {loading ? <p style={styles.empty}>Loading authorised review queue…</p> : rows.length === 0 ? <p style={styles.empty}>No submitted timesheets are waiting for review.</p> : (
          <div style={{ overflowX: 'auto' }}>
            <table style={styles.table}>
              <thead>
                <tr>
                  <th style={styles.th}>Worker</th>
                  <th style={styles.th}>Site / role</th>
                  <th style={styles.th}>Shift</th>
                  <th style={styles.th}>Payable</th>
                  <th style={styles.th}>Review signal</th>
                  <th style={styles.th}>Submitted</th>
                  <th style={styles.th}>Action</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => {
                  const isException = row.exception_label !== 'Clean';
                  const rejecting = rejectingId === row.timesheet_id;
                  return (
                    <tr key={row.timesheet_id}>
                      <td style={styles.tdStrong}>{row.worker_label}</td>
                      <td style={styles.td}><strong style={{ color: '#101828' }}>{row.site_name}</strong><br />{row.role_name}</td>
                      <td style={styles.td}>{formatDateTime(row.starts_at)}<br /><span style={styles.muted}>to {formatDateTime(row.ends_at)}</span></td>
                      <td style={styles.td}>{hours(row.payable_minutes)}</td>
                      <td style={styles.td}><span style={isException ? styles.exception : styles.clean}>{row.exception_label}</span></td>
                      <td style={styles.td}>{formatDateTime(row.submitted_at)}</td>
                      <td style={styles.td}>
                        <div style={styles.actions}>
                          <button type="button" disabled={busyId !== null || mode === 'staging'} onClick={() => void review(row.timesheet_id, 'approve')} style={styles.approveButton}>Approve</button>
                          <button type="button" disabled={busyId !== null || mode === 'staging'} onClick={() => { setRejectingId(row.timesheet_id); setReason(''); }} style={styles.rejectButton}>Reject</button>
                        </div>
                        {rejecting && (
                          <div style={styles.rejectBox}>
                            <label style={styles.label}>Rejection reason
                              <textarea aria-label={`Rejection reason for ${row.worker_label}`} value={reason} maxLength={500} onChange={(event) => setReason(event.target.value)} style={styles.textarea} />
                            </label>
                            <div style={styles.actions}>
                              <button type="button" disabled={busyId !== null} onClick={() => void review(row.timesheet_id, 'reject')} style={styles.rejectConfirm}>Confirm rejection</button>
                              <button type="button" disabled={busyId !== null} onClick={() => { setRejectingId(null); setReason(''); }} style={styles.cancelButton}>Cancel</button>
                            </div>
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <p style={styles.note}>Security: the queue returns a pseudonymous worker label and site-scoped operational fields only. Approval/rejection is performed by the audited server-side review RPC, which re-checks the reviewer role and supervisor-site assignment before changing timesheet state.</p>
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
  cards: { maxWidth: 1200, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 12 },
  card: { background: '#fff', border: '1px solid #e8ecf2', borderRadius: 14, padding: 16, display: 'grid', gap: 8 },
  cardLabel: { color: '#667085', fontSize: 12, fontWeight: 650 },
  cardValue: { fontSize: 24, letterSpacing: '-0.03em' },
  toolbar: { maxWidth: 1200, margin: '0 auto 12px', display: 'flex', justifyContent: 'flex-end' },
  secondaryButton: { minHeight: 44, border: '1px solid #d0d5dd', borderRadius: 10, background: '#fff', color: '#344054', padding: '0 14px', fontWeight: 700, cursor: 'pointer' },
  message: { maxWidth: 1168, margin: '0 auto 16px', border: '1px solid #c7d2fe', borderRadius: 12, background: '#eef2ff', color: '#3730a3', padding: '12px 16px', fontSize: 13 },
  panel: { maxWidth: 1200, margin: '0 auto', background: '#fff', border: '1px solid #e8ecf2', borderRadius: 16, padding: 18 },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 },
  th: { textAlign: 'left', padding: '11px 9px', color: '#667085', borderBottom: '1px solid #eaecf0', whiteSpace: 'nowrap' },
  td: { padding: '13px 9px', borderBottom: '1px solid #f0f2f5', color: '#475467', verticalAlign: 'top', minWidth: 110 },
  tdStrong: { padding: '13px 9px', borderBottom: '1px solid #f0f2f5', color: '#101828', fontWeight: 750, verticalAlign: 'top', whiteSpace: 'nowrap' },
  muted: { color: '#98a2b3' },
  clean: { display: 'inline-block', color: '#027a48', background: '#ecfdf3', borderRadius: 999, padding: '5px 8px', fontWeight: 750, whiteSpace: 'nowrap' },
  exception: { display: 'inline-block', color: '#b42318', background: '#fef3f2', borderRadius: 999, padding: '5px 8px', fontWeight: 750, whiteSpace: 'nowrap' },
  actions: { display: 'flex', flexWrap: 'wrap', gap: 8 },
  approveButton: { minHeight: 40, border: 0, borderRadius: 9, background: '#027a48', color: '#fff', padding: '0 12px', fontWeight: 750, cursor: 'pointer' },
  rejectButton: { minHeight: 40, border: '1px solid #fda29b', borderRadius: 9, background: '#fff', color: '#b42318', padding: '0 12px', fontWeight: 750, cursor: 'pointer' },
  rejectBox: { marginTop: 10, minWidth: 260, display: 'grid', gap: 8, padding: 10, border: '1px solid #fecaca', borderRadius: 10, background: '#fff7f7' },
  label: { display: 'grid', gap: 6, color: '#475467', fontSize: 12, fontWeight: 650 },
  textarea: { minHeight: 76, resize: 'vertical', border: '1px solid #d0d5dd', borderRadius: 8, padding: 9, fontSize: 16, color: '#101828', background: '#fff' },
  rejectConfirm: { minHeight: 40, border: 0, borderRadius: 9, background: '#b42318', color: '#fff', padding: '0 12px', fontWeight: 750, cursor: 'pointer' },
  cancelButton: { minHeight: 40, border: '1px solid #d0d5dd', borderRadius: 9, background: '#fff', color: '#344054', padding: '0 12px', fontWeight: 700, cursor: 'pointer' },
  empty: { color: '#667085', textAlign: 'center', padding: 30 },
  note: { maxWidth: 1168, margin: '14px auto 0', color: '#667085', fontSize: 12, lineHeight: 1.5 },
};
