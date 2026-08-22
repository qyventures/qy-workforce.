'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';
import { supabase } from '../../../lib/supabase';

type Site = { id: string; name: string; clients: { name: string } | null };
type Role = { id: string; name: string };
type Shift = { id: string; starts_at: string; ends_at: string; headcount: number; status: string; sites: { name: string } | null; roles: { name: string } | null };

const fieldStyle = { border: '1px solid #D0D5DD', borderRadius: 9, padding: '10px 11px', fontSize: 14, width: '100%', boxSizing: 'border-box' as const };

export default function ShiftsPage() {
  const [sites, setSites] = useState<Site[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [shifts, setShifts] = useState<Shift[]>([]);
  const [siteId, setSiteId] = useState('');
  const [roleId, setRoleId] = useState('');
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');
  const [headcount, setHeadcount] = useState('1');
  const [workerRate, setWorkerRate] = useState('');
  const [clientRate, setClientRate] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  const margin = useMemo(() => {
    const cost = Number(workerRate); const revenue = Number(clientRate);
    return revenue > 0 && cost >= 0 ? ((revenue - cost) / revenue) * 100 : null;
  }, [workerRate, clientRate]);

  async function load() {
    if (!supabase) return;
    const [siteResult, roleResult, shiftResult] = await Promise.all([
      supabase.from('sites').select('id,name,clients(name)').eq('active', true).order('name'),
      supabase.from('roles').select('id,name').eq('active', true).order('name'),
      supabase.from('shifts').select('id,starts_at,ends_at,headcount,status,sites(name),roles(name)').gte('ends_at', new Date().toISOString()).order('starts_at').limit(20),
    ]);
    const error = siteResult.error || roleResult.error || shiftResult.error;
    if (error) { setMessage('Sign in with an authorised Ops account to view live shift demand.'); return; }
    setSites((siteResult.data ?? []) as unknown as Site[]);
    setRoles((roleResult.data ?? []) as Role[]);
    setShifts((shiftResult.data ?? []) as unknown as Shift[]);
  }

  useEffect(() => { void load(); }, []);

  async function createDraft(event: FormEvent) {
    event.preventDefault();
    if (!supabase || busy) return;
    const start = new Date(startsAt); const end = new Date(endsAt);
    if (!siteId || !roleId || Number(headcount) < 1 || !startsAt || !endsAt || end <= start) {
      setMessage('Choose a site and role, then provide a valid future time range and headcount.'); return;
    }
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('create_shift_draft', {
      p_site_id: siteId, p_role_id: roleId, p_starts_at: start.toISOString(), p_ends_at: end.toISOString(),
      p_headcount: Number(headcount), p_worker_rate: Number(workerRate), p_client_rate: Number(clientRate),
    });
    setBusy(false);
    if (error) { setMessage(`Draft not created: ${error.message}`); return; }
    setMessage('Draft created. Review it, then open it only when staffing demand is ready for workers.');
    setStartsAt(''); setEndsAt(''); setHeadcount('1'); setWorkerRate(''); setClientRate('');
    void load();
  }

  async function openShift(id: string) {
    if (!supabase || busy) return;
    setBusy(true); setMessage('');
    const { error } = await supabase.rpc('open_shift', { p_shift_id: id });
    setBusy(false);
    setMessage(error ? `Unable to open shift: ${error.message}` : 'Shift opened and the publication event was audited.');
    if (!error) void load();
  }

  return <section style={styles.page}>
    <header style={styles.header}><div><div style={styles.eyebrow}>OPERATIONS / SHIFTS</div><h1 style={styles.h1}>Shift demand</h1><p style={styles.sub}>Create auditable drafts, review margin, and publish only validated future demand.</p></div></header>
    {!supabase && <p style={styles.notice}>Live actions are disabled until the staging Supabase public environment is configured.</p>}
    {message && <p aria-live="polite" style={styles.notice}>{message}</p>}
    <section style={styles.panel}><h2 style={styles.h2}>Create draft</h2><form onSubmit={createDraft} style={styles.form}>
      <label>Client site<select required value={siteId} onChange={(e) => setSiteId(e.target.value)} style={fieldStyle}><option value="">Select a site</option>{sites.map((site) => <option key={site.id} value={site.id}>{site.clients?.name ?? 'Client'} · {site.name}</option>)}</select></label>
      <label>Role<select required value={roleId} onChange={(e) => setRoleId(e.target.value)} style={fieldStyle}><option value="">Select a role</option>{roles.map((role) => <option key={role.id} value={role.id}>{role.name}</option>)}</select></label>
      <label>Starts<input required type="datetime-local" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} style={fieldStyle}/></label>
      <label>Ends<input required type="datetime-local" value={endsAt} onChange={(e) => setEndsAt(e.target.value)} style={fieldStyle}/></label>
      <label>Headcount<input required min="1" max="500" type="number" value={headcount} onChange={(e) => setHeadcount(e.target.value)} style={fieldStyle}/></label>
      <label>Worker rate<input required min="0" max="1000" step="0.01" inputMode="decimal" type="number" value={workerRate} onChange={(e) => setWorkerRate(e.target.value)} style={fieldStyle}/></label>
      <label>Client rate<input required min="0" max="1000" step="0.01" inputMode="decimal" type="number" value={clientRate} onChange={(e) => setClientRate(e.target.value)} style={fieldStyle}/></label>
      <div style={styles.margin}>{margin === null ? 'Enter rates to preview margin' : <><strong>{margin.toFixed(1)}%</strong> estimated gross margin {margin < 10 && <span style={styles.warn}>Review low margin</span>}</>}</div>
      <button disabled={!supabase || busy} style={styles.primary}>{busy ? 'Working…' : 'Create draft'}</button>
    </form></section>
    <section style={styles.panel}><h2 style={styles.h2}>Upcoming demand</h2>{shifts.length === 0 ? <p style={styles.muted}>No future shifts visible to this account.</p> : <div style={{ overflowX: 'auto' }}><table style={styles.table}><thead><tr><th style={styles.th}>Role</th><th style={styles.th}>Site</th><th style={styles.th}>Schedule</th><th style={styles.th}>Needed</th><th style={styles.th}>Status</th><th style={styles.th}>Action</th></tr></thead><tbody>{shifts.map((shift) => <tr key={shift.id}><td style={styles.strong}>{shift.roles?.name ?? 'Role'}</td><td style={styles.td}>{shift.sites?.name ?? 'Site'}</td><td style={styles.td}>{new Date(shift.starts_at).toLocaleString()} – {new Date(shift.ends_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</td><td style={styles.td}>{shift.headcount}</td><td style={styles.td}><span style={styles.status}>{shift.status}</span></td><td style={styles.td}>{shift.status === 'draft' ? <button disabled={busy || !supabase} onClick={() => void openShift(shift.id)} style={styles.secondary}>Open shift</button> : '—'}</td></tr>)}</tbody></table></div>}</section>
    <p style={styles.foot}>Rates and shift state are validated again in audited RPCs. This page does not expose worker identity or create assignments.</p>
  </section>;
}

const styles: Record<string, any> = {
  page: { padding: 32, background: '#f5f7fb', minHeight: '100vh', color: '#101828' }, header: { maxWidth: 1180, margin: '0 auto 20px' }, eyebrow: { fontSize: 12, letterSpacing: 1.2, fontWeight: 800, color: '#4D63FF' }, h1: { margin: '5px 0', fontSize: 32 }, sub: { margin: 0, color: '#667085' }, h2: { margin: '0 0 16px', fontSize: 18 }, panel: { maxWidth: 1140, margin: '0 auto 16px', padding: 20, background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16 }, form: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(185px,1fr))', gap: 14, alignItems: 'end' }, notice: { maxWidth: 1110, margin: '0 auto 16px', padding: 13, borderRadius: 10, background: '#EEF2FF', color: '#3730A3', fontSize: 13 }, margin: { color: '#475467', fontSize: 13, minHeight: 38, alignContent: 'center' }, warn: { marginLeft: 7, color: '#B54708', fontWeight: 700 }, primary: { border: 0, borderRadius: 9, padding: '11px 14px', background: '#111827', color: '#fff', fontWeight: 750, cursor: 'pointer' }, secondary: { border: '1px solid #D0D5DD', borderRadius: 8, padding: '7px 10px', background: '#fff', fontWeight: 700, cursor: 'pointer' }, table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', padding: '10px 8px', color: '#667085', borderBottom: '1px solid #EAECF0' }, td: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467' }, strong: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', fontWeight: 700 }, status: { padding: '4px 8px', background: '#F2F4F7', borderRadius: 999, fontWeight: 700, fontSize: 12 }, muted: { color: '#667085' }, foot: { maxWidth: 1140, margin: '0 auto', color: '#98A2B3', fontSize: 12 },
};
