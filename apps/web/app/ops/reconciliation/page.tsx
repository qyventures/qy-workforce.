'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '../../../lib/supabase';

type CaseStatus = 'open' | 'investigating' | 'resolved' | 'dismissed';
type CaseType = 'missing_payroll_item' | 'missing_payout' | 'missing_billing_item' | 'worker_amount_mismatch' | 'client_amount_mismatch' | 'payout_amount_mismatch';

type ReconciliationCase = {
  id: string;
  timesheet_id: string;
  case_type: CaseType;
  expected_amount: number | null;
  observed_amount: number | null;
  status: CaseStatus;
  resolution_note: string | null;
  detected_at: string;
  updated_at: string;
};

const labels: Record<CaseType, string> = {
  missing_payroll_item: 'Missing payroll item',
  missing_payout: 'Missing worker payout',
  missing_billing_item: 'Missing client billing item',
  worker_amount_mismatch: 'Worker amount mismatch',
  client_amount_mismatch: 'Client amount mismatch',
  payout_amount_mismatch: 'Payout amount mismatch',
};

function defaultStart() {
  const date = new Date();
  date.setDate(date.getDate() - 30);
  return date.toISOString().slice(0, 10);
}

function money(value: number | null) {
  return value == null ? '—' : `S$${Number(value).toFixed(2)}`;
}

export default function ReconciliationPage() {
  const [start, setStart] = useState(defaultStart);
  const [end, setEnd] = useState(() => new Date().toISOString().slice(0, 10));
  const [cases, setCases] = useState<ReconciliationCase[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  const openCount = useMemo(() => cases.filter((item) => item.status === 'open' || item.status === 'investigating').length, [cases]);

  async function load() {
    if (!supabase) { setMessage('Staging Supabase is not configured; live reconciliation actions are disabled.'); setLoading(false); return; }
    setLoading(true); setMessage('');
    const { data, error } = await supabase
      .from('financial_reconciliation_cases')
      .select('id,timesheet_id,case_type,expected_amount,observed_amount,status,resolution_note,detected_at,updated_at')
      .order('status', { ascending: true })
      .order('detected_at', { ascending: false });
    if (error) { setCases([]); setMessage(error.message.includes('permission') || error.message.includes('authori') ? 'Sign in with an authorised finance or admin account to view reconciliation cases.' : `Unable to load cases: ${error.message}`); }
    else setCases((data ?? []) as ReconciliationCase[]);
    setLoading(false);
  }

  useEffect(() => { void load(); }, []);

  async function sync() {
    if (!supabase || busy || !start || !end) return;
    setBusy(true); setMessage('');
    const { data, error } = await supabase.rpc('sync_financial_reconciliation_cases', { p_start: start, p_end: end });
    if (error) setMessage(`Reconciliation scan failed: ${error.message}`);
    else { setMessage(`${Number(data ?? 0)} new case(s) found. Existing cases were preserved.`); await load(); }
    setBusy(false);
  }

  async function transition(item: ReconciliationCase, status: 'investigating' | 'resolved' | 'dismissed') {
    if (!supabase || busy) return;
    const prompt = status === 'investigating' ? 'Investigation note (5–1,000 characters; do not include personal data):' : status === 'resolved' ? 'Resolution note (5–1,000 characters; do not include personal data):' : 'Dismissal note (5–1,000 characters; do not include personal data):';
    const note = window.prompt(prompt)?.trim() || '';
    if (note.length < 5 || note.length > 1000) { setMessage('A note between 5 and 1,000 characters is required.'); return; }
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('transition_financial_reconciliation_case', { p_case: item.id, p_status: status, p_note: note });
    if (error) setMessage(`Case update failed: ${error.message}`);
    else { setMessage(`Case marked ${status}. The change was audited.`); await load(); }
    setBusy(false);
  }

  return (
    <main style={styles.page}>
      <div style={styles.wrap}>
        <Link href="/ops" style={styles.back}>← Operations</Link>
        <header style={styles.header}>
          <div><div style={styles.eyebrow}>FINANCE / CONTROL</div><h1 style={styles.h1}>Financial reconciliation</h1><p style={styles.sub}>Find drift between approved timesheets, payroll, worker payouts and client billing.</p></div>
          <div style={styles.headerActions}><span style={styles.count}>{openCount} active</span><button disabled={!supabase || busy || !start || !end} onClick={() => void sync()} style={styles.primary}>{busy ? 'Working…' : 'Scan period'}</button></div>
        </header>

        <section style={styles.panel}>
          <div style={styles.controls}><label>From<br /><input type="date" value={start} onChange={(event) => setStart(event.target.value)} style={styles.input} /></label><label>To<br /><input type="date" value={end} onChange={(event) => setEnd(event.target.value)} style={styles.input} /></label><p style={styles.help}>The scan is advisory and only adds deduplicated cases. It never changes payroll, payout or billing records.</p></div>
        </section>
        {message && <section role="status" style={styles.message}>{message}</section>}
        <section style={styles.panel}>
          {loading ? <p style={styles.empty}>Loading authorised cases…</p> : cases.length === 0 ? <p style={styles.empty}>No reconciliation cases are visible to this account.</p> : <div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr>{['Issue', 'Timesheet reference', 'Expected', 'Observed', 'Detected', 'Status', 'Action'].map((heading) => <th key={heading} style={styles.th}>{heading}</th>)}</tr></thead><tbody>{cases.map((item) => <tr key={item.id}><td style={styles.strong}>{labels[item.case_type]}</td><td style={styles.td}><code>{item.timesheet_id.slice(0, 8)}…</code></td><td style={styles.td}>{money(item.expected_amount)}</td><td style={styles.td}>{money(item.observed_amount)}</td><td style={styles.td}>{new Date(item.detected_at).toLocaleDateString()}</td><td style={styles.td}><span style={item.status === 'open' || item.status === 'investigating' ? styles.warn : styles.ok}>{item.status}</span>{item.resolution_note && <div style={styles.note}>{item.resolution_note}</div>}</td><td style={styles.td}><div style={styles.actions}>{item.status === 'open' && <button disabled={busy} onClick={() => void transition(item, 'investigating')}>Investigate</button>}{(item.status === 'open' || item.status === 'investigating') && <><button disabled={busy} onClick={() => void transition(item, 'resolved')}>Resolve</button><button disabled={busy} onClick={() => void transition(item, 'dismissed')} style={styles.danger}>Dismiss</button></>}</div></td></tr>)}</tbody></table></div>}
        </section>
        <p style={styles.footer}><strong>Control boundary:</strong> cases contain no worker name, NRIC, bank details or raw attendance location. RLS controls visibility; state changes are allowed only through audited RPCs and do not repair source ledgers automatically.</p>
      </div>
    </main>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#f5f7fb', padding: '32px 20px', color: '#111827', fontFamily: 'Arial, sans-serif' }, wrap: { maxWidth: 1240, margin: '0 auto' }, back: { color: '#475569', textDecoration: 'none' }, header: { display: 'flex', justifyContent: 'space-between', alignItems: 'end', gap: 20, flexWrap: 'wrap', margin: '22px 0' }, headerActions: { display: 'flex', alignItems: 'center', gap: 10 }, eyebrow: { color: '#4d63ff', fontSize: 12, fontWeight: 800, letterSpacing: 1.2 }, h1: { fontSize: 34, margin: '5px 0 8px' }, sub: { color: '#64748b', margin: 0 }, count: { color: '#475569', fontWeight: 700 }, primary: { padding: '11px 16px', border: 0, borderRadius: 9, background: '#111827', color: '#fff', fontWeight: 700 }, panel: { background: '#fff', borderRadius: 16, padding: 20, boxShadow: '0 5px 20px rgba(15,23,42,.05)', marginTop: 16 }, controls: { display: 'flex', gap: 14, alignItems: 'end', flexWrap: 'wrap' }, input: { padding: 10, marginTop: 6, border: '1px solid #cbd5e1', borderRadius: 8 }, help: { color: '#64748b', fontSize: 13, maxWidth: 620, margin: 0, lineHeight: 1.5 }, message: { padding: 14, background: '#eef2ff', color: '#3730a3', borderRadius: 12, marginTop: 16 }, empty: { color: '#64748b', textAlign: 'center', padding: 28 }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#64748b', padding: 10, borderBottom: '1px solid #e5e7eb', whiteSpace: 'nowrap' }, td: { padding: 12, borderBottom: '1px solid #f1f5f9', color: '#475569', verticalAlign: 'top' }, strong: { padding: 12, borderBottom: '1px solid #f1f5f9', fontWeight: 750, whiteSpace: 'nowrap' }, warn: { color: '#b54708', background: '#fffaeb', padding: '5px 8px', borderRadius: 999, fontWeight: 700 }, ok: { color: '#027a48', background: '#ecfdf3', padding: '5px 8px', borderRadius: 999, fontWeight: 700 }, actions: { display: 'flex', gap: 6, flexWrap: 'wrap' }, danger: { color: '#b42318' }, note: { marginTop: 8, color: '#64748b', maxWidth: 220, lineHeight: 1.4 }, footer: { color: '#64748b', fontSize: 12, lineHeight: 1.5, margin: '14px 2px' },
};
