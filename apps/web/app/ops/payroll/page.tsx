'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '../../../lib/supabase';

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

  const configured = Boolean(supabase);
  const sorted = useMemo(() => [...batches].sort((a, b) => b.created_at.localeCompare(a.created_at)), [batches]);

  async function load() {
    if (!supabase) return;
    const { data, error } = await supabase
      .from('payroll_batches')
      .select('id,period_start,period_end,status,export_count,created_at')
      .order('created_at', { ascending: false });
    if (error) setMessage(error.message);
    else setBatches((data ?? []) as Batch[]);
  }

  useEffect(() => { void load(); }, []);

  async function createBatch() {
    if (!supabase || !start || !end) return;
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('create_payroll_batch', { p_start: start, p_end: end });
    setBusy(false);
    if (error) setMessage(error.message);
    else { setMessage('Draft payroll batch created.'); void load(); }
  }

  async function lockBatch(id: string) {
    if (!supabase) return;
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('lock_payroll_batch', { p_batch: id });
    setBusy(false);
    if (error) setMessage(error.message);
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
    if (error) setMessage(error.message.includes('only a draft') ? 'This batch is no longer a draft. Refresh and review its current status.' : error.message);
    else { setMessage('Draft cancelled. Its timesheets are available for a new payroll batch and the reason was audited.'); void load(); }
  }

  async function exportCsv(batch: Batch) {
    if (!supabase) return;
    setBusy(true); setMessage('');
    const { data, error } = await supabase.rpc('get_payroll_export', { p_batch: batch.id });
    if (error) { setBusy(false); setMessage(error.message); return; }

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
    if (audit.error) { setBusy(false); setMessage(audit.error.message); return; }

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

  return (
    <main style={{ minHeight: '100vh', background: '#f5f7fb', padding: '32px 20px', fontFamily: 'Arial, sans-serif', color: '#111827' }}>
      <div style={{ maxWidth: 1100, margin: '0 auto' }}>
        <Link href="/ops" style={{ color: '#475569', textDecoration: 'none' }}>← Operations</Link>
        <h1 style={{ fontSize: 34, marginBottom: 8 }}>Payroll control</h1>
        <p style={{ color: '#64748b', marginTop: 0 }}>Finance-only batch creation, locking and auditable payroll export. Payment credentials are intentionally kept outside QY Workforce.</p>

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
                </div>
              </div>
            ))}
            {configured && sorted.length === 0 && <p style={{ color: '#64748b' }}>No payroll batches yet.</p>}
          </div>
        </section>
      </div>
    </main>
  );
}
