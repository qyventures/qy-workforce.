'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '../../../lib/supabase';
import { safeOpsError } from '../../../lib/ops';

type Batch = {
  id: string;
  period_start: string;
  period_end: string;
  status: 'draft' | 'locked' | 'exported' | 'cancelled';
  export_count: number | null;
  created_at: string;
};

type ExportRow = {
  batch_id: string;
  timesheet_id: string;
  worker_reference: string;
  worker_name: string;
  shift_date: string;
  site_name: string;
  payable_minutes: number;
  gross_pay: number;
  currency: string;
};

type Payout = {
  payout_id: string;
  batch_item_id: string;
  worker_label: string;
  shift_date: string;
  site_name: string;
  base_amount: number;
  adjustment_amount: number;
  payable_amount: number;
  currency: string;
  method: 'bank' | 'cash_exception' | 'other';
  status: 'pending' | 'approved' | 'processing' | 'paid' | 'failed' | 'cancelled';
  external_reference: string | null;
  prepared_by_me: boolean;
};

function csvCell(value: unknown) {
  const text = String(value ?? '');
  return `"${text.replaceAll('"', '""')}"`;
}

async function sha256(text: string) {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export default function PayrollPage() {
  const [batches, setBatches] = useState<Batch[]>([]);
  const [start, setStart] = useState('');
  const [end, setEnd] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [selectedBatch, setSelectedBatch] = useState<Batch | null>(null);
  const [payouts, setPayouts] = useState<Payout[]>([]);

  const configured = Boolean(supabase);
  const sorted = useMemo(() => [...batches].sort((a, b) => b.created_at.localeCompare(a.created_at)), [batches]);

  async function load() {
    if (!supabase) return;
    const { data, error } = await supabase
      .from('payroll_batches')
      .select('id,period_start,period_end,status,export_count,created_at')
      .order('created_at', { ascending: false });
    if (error) setMessage(safeOpsError(error, 'Unable to load payroll batches. No records were changed.'));
    else setBatches((data ?? []) as Batch[]);
  }

  useEffect(() => { void load(); }, []);

  async function createBatch() {
    if (!supabase || !start || !end) return;
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('create_payroll_batch', { p_start: start, p_end: end });
    setBusy(false);
    if (error) setMessage(safeOpsError(error, 'Unable to create the payroll batch. No records were changed.'));
    else { setMessage('Draft payroll batch created.'); void load(); }
  }

  async function lockBatch(id: string) {
    if (!supabase) return;
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('lock_payroll_batch', { p_batch: id });
    setBusy(false);
    if (error) setMessage(safeOpsError(error, 'Unable to lock the payroll batch. No records were changed.'));
    else { setMessage('Batch locked. It can now be exported.'); void load(); }
  }

  async function cancelBatch(batch: Batch) {
    if (!supabase || busy || batch.status !== 'draft') return;
    const reason = window.prompt('Why is this draft being cancelled? (10–500 characters; do not include sensitive personal data)')?.trim();
    if (!reason) return;
    if (reason.length < 10 || reason.length > 500) {
      setMessage('Cancellation reason must be between 10 and 500 characters.');
      return;
    }
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('cancel_payroll_batch', { p_batch: batch.id, p_reason: reason });
    setBusy(false);
    if (error) setMessage(error.message.includes('only a draft') ? 'This batch is no longer a draft. Refresh and review its current status.' : safeOpsError(error, 'Unable to cancel this draft. No records were changed.'));
    else { setMessage('Draft cancelled. Its timesheets are available for a new payroll batch and the reason was audited.'); void load(); }
  }

  async function exportCsv(batch: Batch) {
    if (!supabase) return;
    setBusy(true); setMessage('');
    const { data, error } = await supabase.rpc('get_payroll_export', { p_batch: batch.id });
    if (error) { setBusy(false); setMessage(safeOpsError(error, 'Unable to prepare the payroll export. No file was created.')); return; }

    const rows = (data ?? []) as ExportRow[];
    const header = ['timesheet_id','worker_reference','worker_name','shift_date','site_name','payable_minutes','gross_pay','currency'];
    const lines = rows.map((r) => [r.timesheet_id,r.worker_reference,r.worker_name,r.shift_date,r.site_name,r.payable_minutes,Number(r.gross_pay).toFixed(2),r.currency].map(csvCell).join(','));
    const csv = [header.join(','), ...lines].join('\n');
    const checksum = await sha256(csv);

    const audit = await supabase.rpc('record_payroll_export', {
      p_batch: batch.id,
      p_format: 'csv',
      p_checksum: checksum,
      p_count: rows.length,
    });
    if (audit.error) { setBusy(false); setMessage(safeOpsError(audit.error, 'The export audit could not be recorded, so no file was downloaded.')); return; }

    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `qy-workforce-payroll-${batch.period_start}-${batch.period_end}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    setBusy(false);
    setMessage(`Exported ${rows.length} payroll rows. SHA-256 audit checksum recorded.`);
    void load();
  }

  async function loadPayouts(batch: Batch) {
    if (!supabase) return;
    setBusy(true); setMessage('');
    const { data, error } = await supabase.rpc('get_worker_payout_control_queue', { p_batch: batch.id });
    setBusy(false);
    if (error) { setMessage(safeOpsError(error, 'Unable to load payout controls. No records were changed.')); return; }
    setSelectedBatch(batch);
    setPayouts((data ?? []) as Payout[]);
  }

  async function preparePayouts(batch: Batch) {
    if (!supabase || busy) return;
    setBusy(true); setMessage('');
    const { data, error } = await supabase.rpc('prepare_worker_payouts', { p_batch: batch.id });
    setBusy(false);
    if (error) { setMessage(safeOpsError(error, 'Unable to prepare worker payouts. No records were changed.')); return; }
    setMessage(`${Number(data ?? 0)} payout records prepared. A different finance user must approve them.`);
    await loadPayouts(batch);
  }

  async function transitionPayout(payout: Payout, status: 'approved' | 'processing' | 'paid' | 'failed' | 'cancelled') {
    if (!supabase || busy) return;
    let reference: string | null = null;
    let method: Payout['method'] | null = null;
    let exceptionReason: string | null = null;
    if (status === 'approved') {
      const choice = window.prompt('Payment method: bank, cash_exception, or other', payout.method)?.trim();
      if (!choice) return;
      if (!['bank', 'cash_exception', 'other'].includes(choice)) { setMessage('Choose bank, cash_exception, or other.'); return; }
      method = choice as Payout['method'];
      if (method === 'cash_exception') {
        exceptionReason = window.prompt('Cash exception reason (5–500 characters; do not include bank details)')?.trim() || null;
        if (!exceptionReason || exceptionReason.length < 5 || exceptionReason.length > 500) { setMessage('A 5–500 character cash exception reason is required.'); return; }
      }
    }
    if (status === 'processing' || status === 'paid') {
      reference = window.prompt('External payment reference (optional; max 200 characters)')?.trim() || null;
      if (reference && reference.length > 200) { setMessage('External payment reference must be 200 characters or fewer.'); return; }
    }
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('set_worker_payout_status', {
      p_payout: payout.payout_id, p_status: status, p_external_reference: reference,
      p_method: method, p_exception_reason: exceptionReason,
    });
    setBusy(false);
    if (error) setMessage(error.message.includes('preparer cannot approve') ? 'Dual control: another finance user must approve this payout.' : safeOpsError(error, 'Unable to update this payout. No status was changed.'));
    else if (selectedBatch) { setMessage(`Payout moved to ${status}. The transition was audited.`); await loadPayouts(selectedBatch); }
  }

  return (
    <main style={{ minHeight: '100vh', background: '#f5f7fb', padding: '32px 20px', fontFamily: 'Arial, sans-serif', color: '#111827' }}>
      <div style={{ maxWidth: 1100, margin: '0 auto' }}>
        <Link href="/ops" style={{ color: '#475569', textDecoration: 'none' }}>← Operations</Link>
        <h1 style={{ fontSize: 34, marginBottom: 8 }}>Payroll control</h1>
        <p style={{ color: '#64748b', marginTop: 0 }}>Finance-only batch creation, locking, dual-control payout tracking and auditable export. Payment credentials remain outside QY Workforce.</p>

        {!configured && <div style={{ padding: 14, background: '#fff7ed', border: '1px solid #fed7aa', borderRadius: 12, margin: '20px 0' }}>Staging Supabase is not configured in this deployment, so live payroll actions are disabled.</div>}
        {message && <div style={{ padding: 14, background: '#eef2ff', borderRadius: 12, margin: '20px 0' }}>{message}</div>}

        <section style={{ background: 'white', borderRadius: 16, padding: 22, boxShadow: '0 8px 30px rgba(15,23,42,.06)', marginTop: 24 }}>
          <h2 style={{ marginTop: 0 }}>Create pay period</h2>
          <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'end' }}>
            <label>Start<br/><input type="date" value={start} onChange={(e) => setStart(e.target.value)} style={{ padding: 10, marginTop: 6 }}/></label>
            <label>End<br/><input type="date" value={end} onChange={(e) => setEnd(e.target.value)} style={{ padding: 10, marginTop: 6 }}/></label>
            <button disabled={!configured || busy || !start || !end} onClick={createBatch} style={{ padding: '11px 18px', borderRadius: 9, border: 0, background: '#111827', color: 'white', cursor: 'pointer' }}>Create draft</button>
          </div>
        </section>

        <section style={{ marginTop: 24 }}>
          <h2>Payroll batches</h2>
          <div style={{ display: 'grid', gap: 12 }}>
            {sorted.map((batch) => (
              <div key={batch.id} style={{ background: 'white', borderRadius: 14, padding: 18, display: 'flex', justifyContent: 'space-between', gap: 18, alignItems: 'center', flexWrap: 'wrap', boxShadow: '0 5px 20px rgba(15,23,42,.05)' }}>
                <div>
                  <strong>{batch.period_start} → {batch.period_end}</strong>
                  <div style={{ color: '#64748b', marginTop: 5 }}>Status: {batch.status}{batch.export_count != null ? ` · ${batch.export_count} rows exported` : ''}</div>
                </div>
                <div style={{ display: 'flex', gap: 8 }}>
                  {batch.status === 'draft' && <button disabled={busy} onClick={() => lockBatch(batch.id)} style={{ padding: '9px 14px' }}>Lock batch</button>}
                  {batch.status === 'draft' && <button disabled={busy} onClick={() => void cancelBatch(batch)} style={{ padding: '9px 14px', color: '#b42318' }}>Cancel draft</button>}
                  {(batch.status === 'locked' || batch.status === 'exported') && <button disabled={busy} onClick={() => exportCsv(batch)} style={{ padding: '9px 14px' }}>Export CSV</button>}
                  {(batch.status === 'locked' || batch.status === 'exported') && <button disabled={busy} onClick={() => void loadPayouts(batch)} style={{ padding: '9px 14px' }}>Payouts</button>}
                </div>
              </div>
            ))}
            {configured && sorted.length === 0 && <p style={{ color: '#64748b' }}>No payroll batches yet.</p>}
          </div>
        </section>

        {selectedBatch && <section style={{ marginTop: 28, background: 'white', borderRadius: 16, padding: 22, boxShadow: '0 8px 30px rgba(15,23,42,.06)' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
            <div><h2 style={{ margin: 0 }}>Worker payouts</h2><p style={{ color: '#64748b', marginBottom: 0 }}>{selectedBatch.period_start} → {selectedBatch.period_end} · worker identities are pseudonymised.</p></div>
            {payouts.length === 0 && <button disabled={busy} onClick={() => void preparePayouts(selectedBatch)} style={{ padding: '10px 14px', background: '#111827', color: 'white', border: 0, borderRadius: 9 }}>Prepare payouts</button>}
          </div>
          {payouts.length === 0 ? <p style={{ color: '#64748b', marginTop: 22 }}>No payouts prepared. All pending adjustments must be independently reviewed first.</p> :
            <div style={{ overflowX: 'auto', marginTop: 20 }}><table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
              <thead><tr>{['Worker / shift','Base','Adjustments','Payable','Method / status','Action'].map((label) => <th key={label} style={{ textAlign: 'left', color: '#64748b', padding: '9px 8px', borderBottom: '1px solid #e5e7eb' }}>{label}</th>)}</tr></thead>
              <tbody>{payouts.map((payout) => <tr key={payout.payout_id}>
                <td style={{ padding: '12px 8px', borderBottom: '1px solid #f1f5f9' }}><strong>{payout.worker_label}</strong><div style={{ color: '#64748b', marginTop: 3 }}>{payout.shift_date} · {payout.site_name}</div></td>
                <td style={{ padding: '12px 8px', borderBottom: '1px solid #f1f5f9' }}>{payout.currency} {Number(payout.base_amount).toFixed(2)}</td>
                <td style={{ padding: '12px 8px', borderBottom: '1px solid #f1f5f9' }}>{Number(payout.adjustment_amount).toFixed(2)}</td>
                <td style={{ padding: '12px 8px', borderBottom: '1px solid #f1f5f9', fontWeight: 800 }}>{Number(payout.payable_amount).toFixed(2)}</td>
                <td style={{ padding: '12px 8px', borderBottom: '1px solid #f1f5f9' }}>{payout.method} · {payout.status}{payout.external_reference ? <div style={{ color: '#64748b' }}>Ref: {payout.external_reference}</div> : null}</td>
                <td style={{ padding: '12px 8px', borderBottom: '1px solid #f1f5f9' }}><div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                  {payout.status === 'pending' && <button disabled={busy || payout.prepared_by_me} title={payout.prepared_by_me ? 'A different finance user must approve' : undefined} onClick={() => void transitionPayout(payout, 'approved')}>Approve</button>}
                  {payout.status === 'approved' && <button disabled={busy} onClick={() => void transitionPayout(payout, 'processing')}>Processing</button>}
                  {(payout.status === 'approved' || payout.status === 'processing') && <button disabled={busy} onClick={() => void transitionPayout(payout, 'paid')}>Mark paid</button>}
                  {payout.status === 'processing' && <button disabled={busy} onClick={() => void transitionPayout(payout, 'failed')}>Failed</button>}
                  {(payout.status === 'pending' || payout.status === 'approved' || payout.status === 'failed') && <button disabled={busy} onClick={() => void transitionPayout(payout, 'cancelled')}>Cancel</button>}
                </div></td>
              </tr>)}</tbody>
            </table></div>}
          <p style={{ color: '#64748b', fontSize: 12, lineHeight: 1.5, marginBottom: 0 }}>Preparation freezes approved adjustment totals. The preparer cannot approve the same payout; every transition is server-validated and audited. Do not enter bank account numbers in references or exception reasons.</p>
        </section>}
      </div>
    </main>
  );
}
