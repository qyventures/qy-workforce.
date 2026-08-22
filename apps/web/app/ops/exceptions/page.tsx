'use client';

import { useMemo, useState } from 'react';

type ExceptionKind = 'Geofence' | 'Duration' | 'Training' | 'Timesheet';
type Priority = 'Critical' | 'High' | 'Medium';

type ExceptionItem = {
  id: string;
  type: ExceptionKind;
  priority: Priority;
  workerAlias: string;
  site: string;
  shift: string;
  detail: string;
  nextAction: string;
};

const stagingExceptions: ExceptionItem[] = [
  {
    id: 'EX-1042',
    type: 'Geofence',
    priority: 'Critical',
    workerAlias: 'Worker W-1842',
    site: 'Hotel Site 03',
    shift: '22 Aug · 07:00–15:00',
    detail: 'Clock-in was recorded outside the configured site radius.',
    nextAction: 'Confirm supervisor evidence before approving payable time.',
  },
  {
    id: 'EX-1040',
    type: 'Duration',
    priority: 'High',
    workerAlias: 'Worker W-0921',
    site: 'Retail Site 07',
    shift: '22 Aug · 09:00–18:00',
    detail: 'Recorded attendance exceeds the scheduled shift by 48 minutes.',
    nextAction: 'Check approved overtime or correct the submitted timesheet.',
  },
  {
    id: 'EX-1038',
    type: 'Training',
    priority: 'High',
    workerAlias: 'Worker W-2218',
    site: 'F&B Site 11',
    shift: '23 Aug · 17:00–23:00',
    detail: 'Required role training is not yet marked complete for tomorrow’s shift.',
    nextAction: 'Complete training verification or replace the assignment.',
  },
  {
    id: 'EX-1036',
    type: 'Timesheet',
    priority: 'Medium',
    workerAlias: 'Worker W-1704',
    site: 'Events Site 02',
    shift: '21 Aug · 14:00–22:00',
    detail: 'Timesheet remains unsubmitted after attendance completion.',
    nextAction: 'Ask the worker to submit before supervisor review.',
  },
];

const priorityRank: Record<Priority, number> = { Critical: 0, High: 1, Medium: 2 };

export default function ExceptionsPage() {
  const [filter, setFilter] = useState<'All' | ExceptionKind>('All');
  const [query, setQuery] = useState('');

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return stagingExceptions
      .filter((item) => filter === 'All' || item.type === filter)
      .filter((item) =>
        !needle ||
        [item.id, item.type, item.workerAlias, item.site, item.shift, item.detail]
          .join(' ')
          .toLowerCase()
          .includes(needle),
      )
      .sort((a, b) => priorityRank[a.priority] - priorityRank[b.priority]);
  }, [filter, query]);

  const critical = stagingExceptions.filter((item) => item.priority === 'Critical').length;
  const high = stagingExceptions.filter((item) => item.priority === 'High').length;

  return (
    <section style={page}>
      <div style={headerRow}>
        <div>
          <p style={eyebrow}>Operations control</p>
          <h1 style={{ margin: 0 }}>Attendance & compliance exceptions</h1>
          <p style={intro}>
            Prioritised staging queue for anomalies that require human review. Worker identities are intentionally pseudonymised.
          </p>
        </div>
        <span style={stagingBadge}>STAGING DATA</span>
      </div>

      <div style={summaryGrid}>
        <Metric label="Open exceptions" value={stagingExceptions.length} note="Across attendance, training and timesheets" />
        <Metric label="Critical" value={critical} note="Review before payroll approval" emphasis />
        <Metric label="High priority" value={high} note="Resolve within the current operations cycle" />
      </div>

      <div style={toolbar}>
        <label style={fieldLabel}>
          Exception type
          <select value={filter} onChange={(event) => setFilter(event.target.value as 'All' | ExceptionKind)} style={control}>
            {['All', 'Geofence', 'Duration', 'Training', 'Timesheet'].map((value) => (
              <option key={value}>{value}</option>
            ))}
          </select>
        </label>
        <label style={{ ...fieldLabel, flex: 1, minWidth: 220 }}>
          Search queue
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Exception ID, worker alias or site"
            style={control}
            aria-label="Search exception queue"
          />
        </label>
      </div>

      <div style={{ display: 'grid', gap: 14 }} aria-live="polite">
        {filtered.length === 0 ? (
          <div style={emptyState}>No exceptions match the current filter.</div>
        ) : (
          filtered.map((item) => (
            <article key={item.id} style={card}>
              <div style={cardTop}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                    <strong>{item.id}</strong>
                    <span style={typePill}>{item.type}</span>
                    <span style={priorityPill(item.priority)}>{item.priority}</span>
                  </div>
                  <p style={meta}>{item.workerAlias} · {item.site} · {item.shift}</p>
                </div>
              </div>
              <p style={{ margin: '12px 0 8px', color: '#344054' }}>{item.detail}</p>
              <div style={actionBox}>
                <strong style={{ fontSize: 13 }}>Recommended next action</strong>
                <span style={{ color: '#667085', fontSize: 13 }}>{item.nextAction}</span>
              </div>
            </article>
          ))
        )}
      </div>

      <p style={note}>
        Resolution actions remain intentionally disabled on this staging screen. Production resolution must use authenticated supervisor/Ops RPCs and create an audit event; no direct client-side attendance or timesheet mutation is allowed.
      </p>
    </section>
  );
}

function Metric({ label, value, note, emphasis = false }: { label: string; value: number; note: string; emphasis?: boolean }) {
  return (
    <article style={{ ...metricCard, borderColor: emphasis ? '#fecdca' : '#e4e7ec' }}>
      <span style={metricLabel}>{label}</span>
      <strong style={{ fontSize: 30, color: emphasis ? '#b42318' : '#101828' }}>{value}</strong>
      <span style={metricNote}>{note}</span>
    </article>
  );
}

const page = { padding: 32, background: '#f5f7fb', minHeight: '100vh', color: '#101828' };
const headerRow = { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 18, flexWrap: 'wrap' as const };
const eyebrow = { margin: '0 0 6px', color: '#475467', textTransform: 'uppercase' as const, letterSpacing: '0.08em', fontSize: 12, fontWeight: 700 };
const intro = { color: '#667085', maxWidth: 760, lineHeight: 1.55, marginBottom: 0 };
const stagingBadge = { padding: '6px 10px', borderRadius: 999, background: '#eef4ff', color: '#3538cd', fontSize: 12, fontWeight: 800 };
const summaryGrid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(190px,1fr))', gap: 14, margin: '24px 0' };
const metricCard = { background: '#fff', border: '1px solid #e4e7ec', borderRadius: 14, padding: 18, display: 'grid', gap: 6 };
const metricLabel = { color: '#475467', fontSize: 13, fontWeight: 700 };
const metricNote = { color: '#98a2b3', fontSize: 12, lineHeight: 1.45 };
const toolbar = { display: 'flex', gap: 14, alignItems: 'end', flexWrap: 'wrap' as const, marginBottom: 18 };
const fieldLabel = { display: 'grid', gap: 6, color: '#344054', fontSize: 13, fontWeight: 700 };
const control = { minHeight: 44, padding: '10px 12px', borderRadius: 10, border: '1px solid #d0d5dd', background: '#fff', color: '#101828', fontSize: 16 };
const card = { background: '#fff', padding: 18, border: '1px solid #e4e7ec', borderRadius: 14 };
const cardTop = { display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' };
const meta = { color: '#667085', fontSize: 13, margin: '8px 0 0' };
const typePill = { padding: '4px 8px', borderRadius: 999, background: '#f2f4f7', color: '#344054', fontSize: 12, fontWeight: 700 };
const priorityPill = (priority: Priority) => ({
  padding: '4px 8px',
  borderRadius: 999,
  background: priority === 'Critical' ? '#fef3f2' : priority === 'High' ? '#fff7ed' : '#f9fafb',
  color: priority === 'Critical' ? '#b42318' : priority === 'High' ? '#c2410c' : '#475467',
  fontSize: 12,
  fontWeight: 800,
});
const actionBox = { display: 'grid', gap: 4, padding: 12, background: '#f9fafb', borderRadius: 10, border: '1px solid #eaecf0' };
const emptyState = { padding: 28, background: '#fff', border: '1px dashed #d0d5dd', borderRadius: 14, color: '#667085', textAlign: 'center' as const };
const note = { fontSize: 12, color: '#98a2b3', marginTop: 18, lineHeight: 1.5 };
