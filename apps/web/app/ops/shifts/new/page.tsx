'use client';

import { FormEvent, useMemo, useState } from 'react';
import { supabase } from '../../../../lib/supabase';

type Draft = {
  siteId: string;
  roleId: string;
  startsAt: string;
  endsAt: string;
  headcount: string;
  workerRate: string;
  clientRate: string;
};

const initial: Draft = { siteId: '', roleId: '', startsAt: '', endsAt: '', headcount: '1', workerRate: '', clientRate: '' };

export default function NewShiftPage() {
  const [draft, setDraft] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  const economics = useMemo(() => {
    const worker = Number(draft.workerRate || 0);
    const client = Number(draft.clientRate || 0);
    const margin = client - worker;
    const pct = client > 0 ? (margin / client) * 100 : 0;
    return { margin, pct };
  }, [draft.workerRate, draft.clientRate]);

  function set<K extends keyof Draft>(key: K, value: Draft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');

    const headcount = Number(draft.headcount);
    const workerRate = Number(draft.workerRate);
    const clientRate = Number(draft.clientRate);
    const startsAt = new Date(draft.startsAt);
    const endsAt = new Date(draft.endsAt);

    if (!draft.siteId || !draft.roleId) return setMessage('Site and role are required.');
    if (!Number.isInteger(headcount) || headcount < 1 || headcount > 500) return setMessage('Headcount must be between 1 and 500.');
    if (!Number.isFinite(workerRate) || workerRate < 0 || !Number.isFinite(clientRate) || clientRate < 0) return setMessage('Rates must be valid non-negative amounts.');
    if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime()) || endsAt <= startsAt) return setMessage('End time must be after start time.');
    if (!supabase) return setMessage('Staging Supabase is not configured. Draft was not submitted.');

    setBusy(true);
    const { error } = await supabase.rpc('create_shift_draft', {
      p_site_id: draft.siteId,
      p_role_id: draft.roleId,
      p_starts_at: startsAt.toISOString(),
      p_ends_at: endsAt.toISOString(),
      p_headcount: headcount,
      p_worker_rate: workerRate,
      p_client_rate: clientRate,
    });

    if (error) {
      setMessage(error.message.includes('function')
        ? 'Secure shift-creation RPC is not deployed to this staging environment yet. Nothing was written.'
        : `Unable to create draft: ${error.message}`);
    } else {
      setDraft(initial);
      setMessage('Shift draft created. Publish/open remains a separate audited action.');
    }
    setBusy(false);
  }

  return (
    <main style={styles.page}>
      <header style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS / SHIFTS</div>
          <h1 style={styles.h1}>Create shift draft</h1>
          <p style={styles.sub}>Create demand safely. Draft creation and later publishing are deliberately separated.</p>
        </div>
        <a href="/ops/shifts" style={styles.back}>Back to shifts</a>
      </header>

      <form onSubmit={(event) => void submit(event)} style={styles.panel}>
        <div style={styles.grid}>
          <label style={styles.label}>Site ID<input aria-label="Site ID" required value={draft.siteId} onChange={(e) => set('siteId', e.target.value.trim())} placeholder="UUID from authorised site directory" style={styles.input} /></label>
          <label style={styles.label}>Role ID<input aria-label="Role ID" required value={draft.roleId} onChange={(e) => set('roleId', e.target.value.trim())} placeholder="UUID from authorised role directory" style={styles.input} /></label>
          <label style={styles.label}>Starts<input aria-label="Shift start" required type="datetime-local" value={draft.startsAt} onChange={(e) => set('startsAt', e.target.value)} style={styles.input} /></label>
          <label style={styles.label}>Ends<input aria-label="Shift end" required type="datetime-local" value={draft.endsAt} onChange={(e) => set('endsAt', e.target.value)} style={styles.input} /></label>
          <label style={styles.label}>Headcount<input aria-label="Headcount" required min={1} max={500} type="number" value={draft.headcount} onChange={(e) => set('headcount', e.target.value)} style={styles.input} /></label>
          <label style={styles.label}>Worker rate / hr (SGD)<input aria-label="Worker hourly rate" required min={0} step="0.01" type="number" value={draft.workerRate} onChange={(e) => set('workerRate', e.target.value)} style={styles.input} /></label>
          <label style={styles.label}>Client rate / hr (SGD)<input aria-label="Client hourly rate" required min={0} step="0.01" type="number" value={draft.clientRate} onChange={(e) => set('clientRate', e.target.value)} style={styles.input} /></label>
        </div>

        <section style={styles.economics} aria-live="polite">
          <div><span>Gross margin / hr</span><strong>S${economics.margin.toFixed(2)}</strong></div>
          <div><span>Gross margin %</span><strong>{economics.pct.toFixed(1)}%</strong></div>
          <div><span>Margin guard</span><strong style={{ color: economics.pct >= 10 ? '#027A48' : '#B42318' }}>{economics.pct >= 10 ? 'At/above 10%' : 'Below 10%'}</strong></div>
        </section>

        {message && <div style={styles.message} role="status">{message}</div>}

        <div style={styles.actions}>
          <button disabled={busy} type="submit" style={styles.primary}>{busy ? 'Creating…' : 'Create draft'}</button>
          <button type="button" onClick={() => { setDraft(initial); setMessage(''); }} style={styles.secondary}>Reset</button>
        </div>
      </form>

      <section style={styles.note}><strong>Least privilege:</strong> this page never writes directly to the shifts table. It calls a server-side `create_shift_draft` RPC, which must enforce Ops/Admin role checks, site/role validity, audit logging, and draft-only status before staging can enable submission.</section>
    </main>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#F5F7FB', padding: 36, color: '#101828' },
  header: { maxWidth: 980, margin: '0 auto 22px', display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center', flexWrap: 'wrap' },
  eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 },
  h1: { fontSize: 34, margin: '5px 0 6px', letterSpacing: '-0.03em' },
  sub: { margin: 0, color: '#667085' },
  back: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #D0D5DD', padding: '10px 13px', borderRadius: 10, background: '#fff' },
  panel: { maxWidth: 980, margin: '0 auto', background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16, padding: 22 },
  grid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(230px,1fr))', gap: 14 },
  label: { display: 'grid', gap: 7, color: '#344054', fontSize: 13, fontWeight: 700 },
  input: { width: '100%', boxSizing: 'border-box', border: '1px solid #D0D5DD', borderRadius: 10, padding: '11px 12px', fontSize: 16, color: '#101828', background: '#fff' },
  economics: { marginTop: 18, display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(170px,1fr))', gap: 10, padding: 14, background: '#F8FAFC', border: '1px solid #EAECF0', borderRadius: 12 },
  message: { marginTop: 14, padding: '11px 13px', background: '#EEF2FF', border: '1px solid #C7D2FE', borderRadius: 10, color: '#3730A3', fontSize: 13 },
  actions: { marginTop: 18, display: 'flex', gap: 10, flexWrap: 'wrap' },
  primary: { border: 0, borderRadius: 10, padding: '11px 15px', background: '#111827', color: '#fff', fontWeight: 800, cursor: 'pointer' },
  secondary: { border: '1px solid #D0D5DD', borderRadius: 10, padding: '11px 15px', background: '#fff', color: '#344054', fontWeight: 800, cursor: 'pointer' },
  note: { maxWidth: 944, margin: '14px auto 0', color: '#667085', fontSize: 12, lineHeight: 1.55 },
};
