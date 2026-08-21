const rows = [
  { worker: 'Worker #1042', site: 'Harbour Hotel', shift: 'Banquet · 18:00–23:00', minutes: 302, flag: 'Clean', status: 'Pending' },
  { worker: 'Worker #1188', site: 'Convention Venue', shift: 'Event Crew · 09:00–18:00', minutes: 574, flag: '+34 min overtime', status: 'Review' },
  { worker: 'Worker #1216', site: 'Lifestyle Retailer', shift: 'Promoter · 12:00–20:00', minutes: 480, flag: 'Geofence exception', status: 'Review' },
];

export default function TimesheetQueue() {
  return (
    <main style={styles.page}>
      <header style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS / TIMESHEETS</div>
          <h1 style={styles.h1}>Approval queue</h1>
          <p style={styles.sub}>Approve clean attendance, investigate exceptions, and prepare payroll-ready records.</p>
        </div>
        <a href="/ops" style={styles.back}>Back to overview</a>
      </header>

      <section style={styles.summary}>
        <div><strong>19</strong><span> pending</span></div>
        <div><strong>12</strong><span> clean matches</span></div>
        <div><strong>7</strong><span> need review</span></div>
      </section>

      <section style={styles.panel}>
        <div style={{ overflowX: 'auto' }}>
          <table style={styles.table}>
            <thead><tr><th style={styles.th}>Worker</th><th style={styles.th}>Site</th><th style={styles.th}>Shift</th><th style={styles.th}>Payable</th><th style={styles.th}>Exception</th><th style={styles.th}>Action</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.worker + r.site}>
                  <td style={styles.strong}>{r.worker}</td>
                  <td style={styles.td}>{r.site}</td>
                  <td style={styles.td}>{r.shift}</td>
                  <td style={styles.td}>{Math.floor(r.minutes / 60)}h {r.minutes % 60}m</td>
                  <td style={styles.td}><span style={r.flag === 'Clean' ? styles.ok : styles.warn}>{r.flag}</span></td>
                  <td style={styles.td}><div style={styles.actions}><button style={styles.approve}>Approve</button><button style={styles.reject}>Reject</button></div></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section style={styles.note}>
        <strong>Security model:</strong> production actions call the server-side review RPC, enforce supervisor/site scope through RLS, and write immutable audit events. Worker names are masked here because this page currently uses staging data.
      </section>
    </main>
  );
}

const styles: Record<string, any> = {
  page: { minHeight: '100vh', background: '#F5F7FB', padding: 36 },
  header: { maxWidth: 1180, margin: '0 auto 22px', display: 'flex', justifyContent: 'space-between', gap: 20, alignItems: 'center' },
  eyebrow: { color: '#4D63FF', fontWeight: 800, fontSize: 12, letterSpacing: 1.2 },
  h1: { fontSize: 34, margin: '5px 0 6px', letterSpacing: '-0.03em' },
  sub: { margin: 0, color: '#667085' },
  back: { color: '#344054', textDecoration: 'none', fontWeight: 700, border: '1px solid #D0D5DD', padding: '10px 13px', borderRadius: 10, background: '#fff' },
  summary: { maxWidth: 1180, margin: '0 auto 16px', display: 'grid', gridTemplateColumns: 'repeat(3,minmax(0,1fr))', gap: 12, fontSize: 14, color: '#667085' },
  panel: { maxWidth: 1180, margin: '0 auto', background: '#fff', border: '1px solid #E8ECF2', borderRadius: 16, padding: 20 },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#98A2B3', padding: '10px 8px', borderBottom: '1px solid #EAECF0' },
  td: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467' }, strong: { padding: '14px 8px', borderBottom: '1px solid #F0F2F5', fontWeight: 750 },
  ok: { color: '#027A48', background: '#ECFDF3', borderRadius: 999, padding: '5px 8px', fontWeight: 700 }, warn: { color: '#B54708', background: '#FFFAEB', borderRadius: 999, padding: '5px 8px', fontWeight: 700 },
  actions: { display: 'flex', gap: 7 }, approve: { border: 0, background: '#111827', color: '#fff', padding: '8px 10px', borderRadius: 8, fontWeight: 700 }, reject: { border: '1px solid #D0D5DD', background: '#fff', color: '#B42318', padding: '8px 10px', borderRadius: 8, fontWeight: 700 },
  note: { maxWidth: 1140, margin: '14px auto 0', padding: '14px 18px', color: '#667085', fontSize: 12, lineHeight: 1.5 },
};
