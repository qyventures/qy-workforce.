import Link from 'next/link';

const metrics = [
  { label: 'Open shifts', value: '42', sub: '11 starting today', href: '/ops/shifts' },
  { label: 'Fill rate', value: '91%', sub: '+4.2 pts this week', href: '/ops/reports' },
  { label: 'Workers on shift', value: '128', sub: '7 sites active', href: '/ops/workers' },
  { label: 'Timesheets pending', value: '19', sub: 'Supervisor approval', href: '/ops/approvals' },
];

const sites = [
  { site: 'Harbour Hotel · Marina Bay', required: 36, filled: 34, risk: '2 gaps', margin: '18.4%' },
  { site: 'City Serviced Residence · Bugis', required: 22, filled: 22, risk: 'Covered', margin: '21.1%' },
  { site: 'Lifestyle Retailer · Orchard', required: 18, filled: 16, risk: '2 gaps', margin: '16.7%' },
  { site: 'Convention Venue · Expo', required: 52, filled: 49, risk: '3 gaps', margin: '19.6%' },
];

const exceptions = [
  '3 workers outside geofence at clock-in',
  '6 timesheets exceed scheduled duration by more than 30 min',
  '2 workers missing required training for tomorrow',
];

export default function OpsDashboard() {
  return (
    <section style={styles.page} aria-labelledby="ops-heading">
      <header style={styles.header}>
        <div>
          <div style={styles.eyebrow}>OPERATIONS</div>
          <h1 id="ops-heading" style={styles.h1}>Workforce command centre</h1>
          <p style={styles.subtitle}>Live staffing, attendance exceptions, approvals and margin visibility.</p>
        </div>
        <Link href="/ops/shifts/new" style={styles.primaryButton}>Create shift</Link>
      </header>

      <div style={styles.metricGrid} aria-label="Operations summary">
        {metrics.map((metric) => (
          <Link key={metric.label} href={metric.href} style={styles.metricCard}>
            <span style={styles.metricLabel}>{metric.label}</span>
            <strong style={styles.metricValue}>{metric.value}</strong>
            <span style={styles.metricSub}>{metric.sub}</span>
          </Link>
        ))}
      </div>

      <div style={styles.twoCol}>
        <section style={styles.panel} aria-labelledby="active-sites-heading">
          <div style={styles.panelHeader}>
            <div>
              <h2 id="active-sites-heading" style={styles.panelTitle}>Active sites</h2>
              <div style={styles.panelSub}>Current fill and estimated gross margin</div>
            </div>
            <Link href="/ops/clients" style={styles.ghostButton}>View clients & sites</Link>
          </div>

          <div style={{ overflowX: 'auto' }}>
            <table style={styles.table}>
              <thead>
                <tr>
                  <th scope="col" style={styles.th}>Site</th>
                  <th scope="col" style={styles.th}>Required</th>
                  <th scope="col" style={styles.th}>Filled</th>
                  <th scope="col" style={styles.th}>Coverage</th>
                  <th scope="col" style={styles.th}>GM</th>
                </tr>
              </thead>
              <tbody>
                {sites.map((row) => (
                  <tr key={row.site}>
                    <td style={styles.tdStrong}>{row.site}</td>
                    <td style={styles.td}>{row.required}</td>
                    <td style={styles.td}>{row.filled}</td>
                    <td style={styles.td}><span style={row.risk === 'Covered' ? styles.okPill : styles.warnPill}>{row.risk}</span></td>
                    <td style={styles.td}>{row.margin}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <aside style={styles.panel} aria-labelledby="attention-heading">
          <h2 id="attention-heading" style={styles.panelTitle}>Needs attention</h2>
          <div style={styles.panelSub}>Exceptions only — no sensitive worker data exposed here.</div>
          <div style={styles.exceptionList}>
            {exceptions.map((item) => (
              <div key={item} style={styles.exceptionItem}>
                <span aria-hidden="true" style={styles.exceptionDot} />
                <span>{item}</span>
              </div>
            ))}
          </div>
          <Link href="/ops/exceptions" style={{ ...styles.ghostButton, display: 'block', textAlign: 'center', marginTop: 18 }}>Review exceptions</Link>
        </aside>
      </div>

      <section style={styles.panel} aria-labelledby="approval-heading">
        <div style={styles.panelHeader}>
          <div>
            <h2 id="approval-heading" style={styles.panelTitle}>Approval queue</h2>
            <div style={styles.panelSub}>19 timesheets pending supervisor or operations approval</div>
          </div>
          <Link href="/ops/approvals" style={styles.ghostButton}>Open queue</Link>
        </div>
        <div style={styles.approvalStrip}>
          <div><strong>12</strong><span> clean matches</span></div>
          <div><strong>5</strong><span> overtime review</span></div>
          <div><strong>2</strong><span> geofence exception</span></div>
        </div>
      </section>

      <p style={styles.disclaimer}>Staging dashboard with demo operational data. Production views remain role-scoped through server-side policies and audited approval/export actions.</p>
    </section>
  );
}

const styles: Record<string, any> = {
  page: { color: '#101828' },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 20, marginBottom: 26 },
  eyebrow: { fontSize: 12, letterSpacing: 1.3, fontWeight: 800, color: '#4D63FF' },
  h1: { fontSize: 32, lineHeight: 1.15, margin: '5px 0 7px', letterSpacing: '-0.03em' },
  subtitle: { color: '#667085', margin: 0, fontSize: 15 },
  primaryButton: { borderRadius: 12, background: '#111827', color: '#fff', padding: '12px 17px', fontWeight: 750, textDecoration: 'none' },
  metricGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 14, marginBottom: 16 },
  metricCard: { background: '#fff', borderRadius: 16, padding: 18, border: '1px solid #E8ECF2', textDecoration: 'none', color: 'inherit', display: 'grid', gap: 5 },
  metricLabel: { color: '#667085', fontSize: 13, fontWeight: 650 },
  metricValue: { fontSize: 30, fontWeight: 850, marginTop: 3, letterSpacing: '-0.03em' },
  metricSub: { color: '#98A2B3', fontSize: 12 },
  twoCol: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 320px), 1fr))', gap: 16, marginBottom: 16 },
  panel: { background: '#fff', borderRadius: 16, padding: 20, border: '1px solid #E8ECF2', minWidth: 0 },
  panelHeader: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12, marginBottom: 16 },
  panelTitle: { fontSize: 17, fontWeight: 800, margin: 0 },
  panelSub: { color: '#98A2B3', fontSize: 12, marginTop: 4 },
  ghostButton: { border: '1px solid #D7DCE4', background: '#fff', borderRadius: 10, padding: '9px 12px', color: '#344054', fontWeight: 700, textDecoration: 'none' },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 },
  th: { color: '#98A2B3', fontWeight: 700, textAlign: 'left', padding: '10px 8px', borderBottom: '1px solid #EAECF0', whiteSpace: 'nowrap' },
  td: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467', whiteSpace: 'nowrap' },
  tdStrong: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#101828', fontWeight: 700, minWidth: 180 },
  okPill: { color: '#027A48', background: '#ECFDF3', padding: '5px 8px', borderRadius: 999, fontWeight: 700, fontSize: 11 },
  warnPill: { color: '#B54708', background: '#FFFAEB', padding: '5px 8px', borderRadius: 999, fontWeight: 700, fontSize: 11 },
  exceptionList: { display: 'grid', gap: 10, marginTop: 17 },
  exceptionItem: { display: 'flex', gap: 10, color: '#475467', fontSize: 13, lineHeight: 1.45, alignItems: 'flex-start' },
  exceptionDot: { width: 8, height: 8, flex: '0 0 auto', borderRadius: 99, background: '#F79009', marginTop: 5 },
  approvalStrip: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 10, color: '#667085', fontSize: 14 },
  disclaimer: { color: '#98A2B3', fontSize: 12, margin: '14px 2px 0' },
};
