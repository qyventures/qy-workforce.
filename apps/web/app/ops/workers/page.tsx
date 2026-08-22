'use client';

import { useMemo, useState } from 'react';

type WorkerRow = {
  alias: string;
  roles: string[];
  readiness: 'Deployable' | 'Review' | 'Blocked';
  training: 'Current' | 'Expiring soon' | 'Missing module';
  vetting: 'Clear' | 'Manual review' | 'Action needed';
  lastUpdated: string;
};

const workers: WorkerRow[] = [
  { alias: 'Worker #A13F9C', roles: ['Banquet', 'F&B'], readiness: 'Deployable', training: 'Current', vetting: 'Clear', lastUpdated: '12 min ago' },
  { alias: 'Worker #B72D41', roles: ['Retail'], readiness: 'Review', training: 'Missing module', vetting: 'Manual review', lastUpdated: '31 min ago' },
  { alias: 'Worker #C05E88', roles: ['Cleaning'], readiness: 'Deployable', training: 'Current', vetting: 'Clear', lastUpdated: '1 hr ago' },
  { alias: 'Worker #D91A27', roles: ['Events', 'Promotions'], readiness: 'Blocked', training: 'Expiring soon', vetting: 'Action needed', lastUpdated: '2 hrs ago' },
];

function tone(value: WorkerRow['readiness']) {
  if (value === 'Deployable') return { background: '#ECFDF3', color: '#027A48' };
  if (value === 'Review') return { background: '#FFFAEB', color: '#B54708' };
  return { background: '#FEF3F2', color: '#B42318' };
}

export default function WorkersPage() {
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<'All' | WorkerRow['readiness']>('All');

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return workers.filter((worker) => {
      const matchesStatus = status === 'All' || worker.readiness === status;
      const matchesQuery = !q || [worker.alias, ...worker.roles, worker.training, worker.vetting]
        .join(' ')
        .toLowerCase()
        .includes(q);
      return matchesStatus && matchesQuery;
    });
  }, [query, status]);

  const deployable = workers.filter((worker) => worker.readiness === 'Deployable').length;
  const attention = workers.length - deployable;

  return (
    <section style={{ padding: 'clamp(20px,4vw,36px)', background: '#F5F7FB', minHeight: '100vh', color: '#101828' }}>
      <div style={{ maxWidth: 1180, margin: '0 auto' }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start', justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <div>
            <p style={{ margin: '0 0 6px', color: '#4D63FF', fontSize: 12, fontWeight: 800, letterSpacing: 1 }}>OPS · WORKERS</p>
            <h1 style={{ margin: 0, fontSize: 'clamp(30px,4vw,44px)' }}>Worker readiness review</h1>
            <p style={{ margin: '10px 0 0', color: '#667085', lineHeight: 1.6, maxWidth: 720 }}>
              Triage deployability, training and vetting without exposing unnecessary identity data in the operations queue.
            </p>
          </div>
          <div style={{ background: '#EEF2FF', color: '#344054', borderRadius: 999, padding: '9px 12px', fontSize: 12, fontWeight: 800 }}>
            STAGING-SAFE VIEW
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(170px,1fr))', gap: 12, marginTop: 28 }}>
          <Metric label="Workers in queue" value={workers.length} />
          <Metric label="Deployable" value={deployable} />
          <Metric label="Needs attention" value={attention} />
          <Metric label="Training issues" value={workers.filter((worker) => worker.training !== 'Current').length} />
        </div>

        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginTop: 24, alignItems: 'end' }}>
          <label style={{ display: 'grid', gap: 6, minWidth: 240, flex: '1 1 320px', color: '#344054', fontSize: 13, fontWeight: 700 }}>
            Search queue
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value.slice(0, 80))}
              placeholder="Worker alias, role, training or vetting"
              aria-label="Search worker review queue"
              style={input}
            />
          </label>
          <label style={{ display: 'grid', gap: 6, minWidth: 180, color: '#344054', fontSize: 13, fontWeight: 700 }}>
            Readiness
            <select value={status} onChange={(event) => setStatus(event.target.value as 'All' | WorkerRow['readiness'])} style={input}>
              <option>All</option>
              <option>Deployable</option>
              <option>Review</option>
              <option>Blocked</option>
            </select>
          </label>
        </div>

        <div style={{ overflowX: 'auto', marginTop: 18, borderRadius: 14, border: '1px solid #E8ECF2', background: '#fff' }}>
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Worker</th>
                <th style={th}>Approved / interested roles</th>
                <th style={th}>Readiness</th>
                <th style={th}>Training</th>
                <th style={th}>Vetting</th>
                <th style={th}>Updated</th>
                <th style={th}>Action</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((worker) => (
                <tr key={worker.alias}>
                  <td style={tdStrong}>{worker.alias}</td>
                  <td style={td}>{worker.roles.join(' · ')}</td>
                  <td style={td}><span style={{ ...pill, ...tone(worker.readiness) }}>{worker.readiness}</span></td>
                  <td style={td}>{worker.training}</td>
                  <td style={td}>{worker.vetting}</td>
                  <td style={td}>{worker.lastUpdated}</td>
                  <td style={td}>
                    <button
                      type="button"
                      disabled
                      aria-label={`Review ${worker.alias}; staging read-only`}
                      title="Production review actions will use authenticated, audited server-side RPCs."
                      style={disabledButton}
                    >
                      Review
                    </button>
                  </td>
                </tr>
              ))}
              {visible.length === 0 && (
                <tr><td colSpan={7} style={{ ...td, textAlign: 'center', padding: 30 }}>No workers match this filter.</td></tr>
              )}
            </tbody>
          </table>
        </div>

        <div style={{ marginTop: 18, display: 'grid', gap: 8, background: '#fff', border: '1px solid #E4E7EC', borderRadius: 14, padding: 16 }}>
          <strong style={{ fontSize: 14 }}>Privacy & control boundary</strong>
          <p style={{ margin: 0, color: '#667085', lineHeight: 1.55, fontSize: 13 }}>
            Operational aliases are used here instead of names, phone numbers, national identifiers or bank details. Production review actions remain disabled until a scoped server RPC can re-check the reviewer role, record the decision reason and write an audit event.
          </p>
        </div>
      </div>
    </section>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return <div style={{ background: '#fff', border: '1px solid #E4E7EC', borderRadius: 14, padding: 16 }}><div style={{ color: '#667085', fontSize: 12, fontWeight: 700 }}>{label}</div><div style={{ marginTop: 6, fontSize: 28, fontWeight: 850 }}>{value}</div></div>;
}

const table = { width: '100%', borderCollapse: 'collapse' as const, minWidth: 920 };
const th = { textAlign: 'left' as const, padding: 12, color: '#667085', borderBottom: '1px solid #EAECF0', fontSize: 12, whiteSpace: 'nowrap' as const };
const td = { padding: 14, borderBottom: '1px solid #F0F2F5', color: '#475467', fontSize: 13, verticalAlign: 'middle' as const };
const tdStrong = { ...td, color: '#101828', fontWeight: 750, whiteSpace: 'nowrap' as const };
const input = { minHeight: 44, border: '1px solid #D0D5DD', borderRadius: 10, padding: '10px 12px', background: '#fff', color: '#101828', fontSize: 16, boxSizing: 'border-box' as const, width: '100%' };
const pill = { display: 'inline-block', borderRadius: 999, padding: '5px 9px', fontWeight: 800, fontSize: 12, whiteSpace: 'nowrap' as const };
const disabledButton = { minHeight: 40, border: '1px solid #D0D5DD', borderRadius: 9, padding: '8px 12px', background: '#F2F4F7', color: '#98A2B3', fontWeight: 750, cursor: 'not-allowed' };
