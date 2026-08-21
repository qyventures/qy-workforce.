const metrics = [
  { label: 'Open shifts', value: '42', sub: '11 starting today' },
  { label: 'Fill rate', value: '91%', sub: '+4.2 pts this week' },
  { label: 'Workers on shift', value: '128', sub: '7 sites active' },
  { label: 'Timesheets pending', value: '19', sub: 'Supervisor approval' },
];

const sites = [
  { site: 'Harbour Hotel · Marina Bay', required: 36, filled: 34, risk: '2 gaps', margin: '18.4%' },
  { site: 'City Serviced Residence · Bugis', required: 22, filled: 22, risk: 'Covered', margin: '21.1%' },
  { site: 'Lifestyle Retailer · Orchard', required: 18, filled: 16, risk: '2 gaps', margin: '16.7%' },
  { site: 'Convention Venue · Expo', required: 52, filled: 49, risk: '3 gaps', margin: '19.6%' },
];

const exceptions = [
  '3 workers outside geofence at clock-in',
  '6 timesheets exceed scheduled duration by >30 min',
  '2 workers missing required training for tomorrow',
];

export default function OpsDashboard() {
  return (
    <main style={styles.page}>
      <aside style={styles.sidebar}>
        <div style={styles.brand}>QY <span style={{ opacity: 0.62 }}>Workforce</span></div>
        <nav style={styles.nav}>
          <a style={styles.navActive}>Overview</a>
          <a style={styles.navItem}>Shifts</a>
          <a style={styles.navItem}>Workers</a>
          <a style={styles.navItem}>Clients & sites</a>
          <a style={styles.navItem}>Timesheets</a>
          <a style={styles.navItem}>Payroll export</a>
          <a style={styles.navItem}>Reports</a>
          <a style={styles.navItem}>Audit & compliance</a>
        </nav>
      </aside>

      <section style={styles.content}>
        <header style={styles.header}>
          <div>
            <div style={styles.eyebrow}>OPERATIONS</div>
            <h1 style={styles.h1}>Workforce command centre</h1>
            <p style={styles.subtitle}>Live staffing, attendance exceptions, approvals and margin visibility.</p>
          </div>
          <button style={styles.primaryButton}>Create shift</button>
        </header>

        <div style={styles.metricGrid}>
          {metrics.map((metric) => (
            <article key={metric.label} style={styles.metricCard}>
              <div style={styles.metricLabel}>{metric.label}</div>
              <div style={styles.metricValue}>{metric.value}</div>
              <div style={styles.metricSub}>{metric.sub}</div>
            </article>
          ))}
        </div>

        <div style={styles.twoCol}>
          <section style={styles.panel}>
            <div style={styles.panelHeader}>
              <div>
                <div style={styles.panelTitle}>Active sites</div>
                <div style={styles.panelSub}>Current fill and estimated gross margin</div>
              </div>
              <button style={styles.ghostButton}>View all</button>
            </div>

            <div style={{ overflowX: 'auto' }}>
              <table style={styles.table}>
                <thead>
                  <tr>
                    <th style={styles.th}>Site</th>
                    <th style={styles.th}>Required</th>
                    <th style={styles.th}>Filled</th>
                    <th style={styles.th}>Coverage</th>
                    <th style={styles.th}>GM</th>
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

          <aside style={styles.panel}>
            <div style={styles.panelTitle}>Needs attention</div>
            <div style={styles.panelSub}>Exceptions only — no sensitive worker data exposed here.</div>
            <div style={styles.exceptionList}>
              {exceptions.map((item) => (
                <div key={item} style={styles.exceptionItem}>
                  <span style={styles.exceptionDot} />
                  <span>{item}</span>
                </div>
              ))}
            </div>
            <button style={{ ...styles.ghostButton, width: '100%', marginTop: 18 }}>Review exceptions</button>
          </aside>
        </div>

        <section style={styles.panel}>
          <div style={styles.panelHeader}>
            <div>
              <div style={styles.panelTitle}>Approval queue</div>
              <div style={styles.panelSub}>19 timesheets pending supervisor or operations approval</div>
            </div>
            <button style={styles.ghostButton}>Open queue</button>
          </div>
          <div style={styles.approvalStrip}>
            <div><strong>12</strong><span> clean matches</span></div>
            <div><strong>5</strong><span> overtime review</span></div>
            <div><strong>2</strong><span> geofence exception</span></div>
          </div>
        </section>

        <p style={styles.disclaimer}>Staging dashboard with demo operational data. Production views will be role-scoped using Supabase RLS and audit every approval/export action.</p>
      </section>
    </main>
  );
}

const styles: Record<string, any> = {
  page: { margin: 0, minHeight: '100vh', background: '#F5F7FB', color: '#101828', fontFamily: 'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif', display: 'grid', gridTemplateColumns: '240px minmax(0, 1fr)' },
  sidebar: { background: '#111827', color: '#fff', padding: '28px 18px', minHeight: '100vh' },
  brand: { fontSize: 19, fontWeight: 850, padding: '0 10px 24px' },
  nav: { display: 'grid', gap: 6 },
  navItem: { color: '#AEB7C6', textDecoration: 'none', padding: '11px 12px', borderRadius: 10, fontSize: 14 },
  navActive: { color: '#fff', background: '#273244', textDecoration: 'none', padding: '11px 12px', borderRadius: 10, fontSize: 14, fontWeight: 700 },
  content: { padding: '36px', minWidth: 0 },
  header: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 20, marginBottom: 26 },
  eyebrow: { fontSize: 12, letterSpacing: 1.3, fontWeight: 800, color: '#4D63FF' },
  h1: { fontSize: 32, lineHeight: 1.15, margin: '5px 0 7px', letterSpacing: '-0.03em' },
  subtitle: { color: '#667085', margin: 0, fontSize: 15 },
  primaryButton: { border: 0, borderRadius: 12, background: '#111827', color: '#fff', padding: '12px 17px', fontWeight: 750, cursor: 'pointer' },
  metricGrid: { display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 14, marginBottom: 16 },
  metricCard: { background: '#fff', borderRadius: 16, padding: 18, border: '1px solid #E8ECF2' },
  metricLabel: { color: '#667085', fontSize: 13, fontWeight: 650 },
  metricValue: { fontSize: 30, fontWeight: 850, marginTop: 8, letterSpacing: '-0.03em' },
  metricSub: { color: '#98A2B3', fontSize: 12, marginTop: 5 },
  twoCol: { display: 'grid', gridTemplateColumns: 'minmax(0, 2fr) minmax(260px, 0.8fr)', gap: 16, marginBottom: 16 },
  panel: { background: '#fff', borderRadius: 16, padding: 20, border: '1px solid #E8ECF2', minWidth: 0 },
  panelHeader: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, marginBottom: 16 },
  panelTitle: { fontSize: 17, fontWeight: 800 },
  panelSub: { color: '#98A2B3', fontSize: 12, marginTop: 4 },
  ghostButton: { border: '1px solid #D7DCE4', background: '#fff', borderRadius: 10, padding: '9px 12px', color: '#344054', fontWeight: 700, cursor: 'pointer' },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 },
  th: { color: '#98A2B3', fontWeight: 700, textAlign: 'left', padding: '10px 8px', borderBottom: '1px solid #EAECF0' },
  td: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#475467' },
  tdStrong: { padding: '13px 8px', borderBottom: '1px solid #F0F2F5', color: '#101828', fontWeight: 700 },
  okPill: { color: '#027A48', background: '#ECFDF3', padding: '5px 8px', borderRadius: 999, fontWeight: 700, fontSize: 11 },
  warnPill: { color: '#B54708', background: '#FFFAEB', padding: '5px 8px', borderRadius: 999, fontWeight: 700, fontSize: 11 },
  exceptionList: { display: 'grid', gap: 10, marginTop: 17 },
  exceptionItem: { display: 'flex', gap: 10, color: '#475467', fontSize: 13, lineHeight: 1.45, alignItems: 'flex-start' },
  exceptionDot: { width: 8, height: 8, flex: '0 0 auto', borderRadius: 99, background: '#F79009', marginTop: 5 },
  approvalStrip: { display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 10, color: '#667085', fontSize: 14 },
  disclaimer: { color: '#98A2B3', fontSize: 12, margin: '14px 2px 0' },
};
