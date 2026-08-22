import Link from 'next/link';

const shifts = [
  { role: 'Banquet Server', site: 'Harbour Hotel', start: 'Today 17:00', required: 24, filled: 22, status: '2 gaps' },
  { role: 'Retail Promoter', site: 'Orchard Flagship', start: 'Today 12:00', required: 12, filled: 12, status: 'Covered' },
  { role: 'Cleaner', site: 'City Residence', start: 'Tomorrow 08:00', required: 18, filled: 15, status: '3 gaps' },
];

export default function ShiftsPage() {
  return (
    <section style={{ padding: 32, background: '#f5f7fb', minHeight: '100vh', color: '#101828' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
        <div>
          <h1>Shift operations</h1>
          <p>Plan demand, monitor fulfilment and open gaps before they become service failures.</p>
        </div>
        <Link href="/ops/shifts/new" style={button}>Create shift draft</Link>
      </div>
      <div style={grid}>
        {shifts.map((s) => (
          <article key={s.role + s.site} style={card}>
            <strong>{s.role}</strong>
            <div>{s.site} · {s.start}</div>
            <div style={{ marginTop: 10 }}>{s.filled}/{s.required} filled</div>
            <span style={s.status === 'Covered' ? ok : warn}>{s.status}</span>
          </article>
        ))}
      </div>
      <p style={note}>Staging data. Draft creation uses a role-gated server RPC; production publish/edit actions remain separately authorised and audited.</p>
    </section>
  );
}

const grid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(240px,1fr))', gap: 14, marginTop: 22 };
const card = { background: '#fff', padding: 18, border: '1px solid #e8ecf2', borderRadius: 14 };
const button = { textDecoration: 'none', borderRadius: 10, padding: '10px 14px', background: '#111827', color: '#fff', fontWeight: 700 };
const ok = { display: 'inline-block', marginTop: 10, padding: '4px 8px', borderRadius: 999, background: '#ecfdf3', color: '#027a48', fontSize: 12, fontWeight: 700 };
const warn = { ...ok, background: '#fff7ed', color: '#c2410c' };
const note = { fontSize: 12, color: '#98a2b3', marginTop: 18 };
