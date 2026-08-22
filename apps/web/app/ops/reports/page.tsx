const accountRows = [
  { account: 'Harbour Hotel', site: 'Marina Bay', scheduled: 2860, filled: 2704, fillRate: '94.5%', billings: '$48,672', workerCost: '$39,184', grossMargin: '$9,488', margin: '19.5%', status: 'Watch' },
  { account: 'City Serviced Residence', site: 'Bugis', scheduled: 1740, filled: 1726, fillRate: '99.2%', billings: '$27,616', workerCost: '$21,510', grossMargin: '$6,106', margin: '22.1%', status: 'Healthy' },
  { account: 'Lifestyle Retailer', site: 'Orchard', scheduled: 1360, filled: 1228, fillRate: '90.3%', billings: '$21,498', workerCost: '$18,167', grossMargin: '$3,331', margin: '15.5%', status: 'At risk' },
  { account: 'Convention Venue', site: 'Expo', scheduled: 4160, filled: 3940, fillRate: '94.7%', billings: '$66,980', workerCost: '$53,441', grossMargin: '$13,539', margin: '20.2%', status: 'Healthy' },
];

const kpis = [
  ['Filled hours', '9,598', '93.9% of scheduled hours'],
  ['Weighted gross margin', '19.5%', 'Target ≥ 18%'],
  ['Revenue at risk', '$4,624', 'Unfilled scheduled demand'],
  ['Exceptions affecting payroll', '11', 'Review before export'],
];

export default function FulfilmentMarginReportPage() {
  return (
    <section style={styles.page}>
      <div style={styles.headingRow}>
        <div>
          <div style={styles.eyebrow}>FULFILMENT & MARGIN</div>
          <h1 style={styles.h1}>Account performance</h1>
          <p style={styles.sub}>Operational visibility only. Production data remains role-scoped and financial exports require server-side authorization and audit logging.</p>
        </div>
        <div style={styles.period}>Current month · staging</div>
      </div>

      <div style={styles.kpiGrid}>
        {kpis.map(([label, value, note]) => (
          <article key={label} style={styles.card}>
            <div style={styles.label}>{label}</div>
            <div style={styles.value}>{value}</div>
            <div style={styles.note}>{note}</div>
          </article>
        ))}
      </div>

      <section style={styles.panel}>
        <div style={styles.panelHeader}>
          <div>
            <h2 style={styles.h2}>Client and site view</h2>
            <p style={styles.note}>Demo figures are intentionally non-personal and contain no worker identifiers.</p>
          </div>
          <div style={styles.legend}><span style={styles.dotOk} /> Healthy <span style={styles.dotWatch} /> Watch <span style={styles.dotRisk} /> At risk</div>
        </div>
        <div style={{ overflowX: 'auto' }}>
          <table style={styles.table}>
            <thead><tr>{['Account','Site','Scheduled hrs','Filled hrs','Fill rate','Billings','Worker cost','Gross margin','GM %','Status'].map((h) => <th key={h} style={styles.th}>{h}</th>)}</tr></thead>
            <tbody>
              {accountRows.map((row) => (
                <tr key={`${row.account}-${row.site}`}>
                  <td style={styles.tdStrong}>{row.account}</td><td style={styles.td}>{row.site}</td><td style={styles.td}>{row.scheduled.toLocaleString()}</td><td style={styles.td}>{row.filled.toLocaleString()}</td><td style={styles.td}>{row.fillRate}</td><td style={styles.td}>{row.billings}</td><td style={styles.td}>{row.workerCost}</td><td style={styles.td}>{row.grossMargin}</td><td style={styles.tdStrong}>{row.margin}</td>
                  <td style={styles.td}><span style={row.status === 'Healthy' ? styles.pillOk : row.status === 'Watch' ? styles.pillWatch : styles.pillRisk}>{row.status}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div style={styles.twoCol}>
        <section style={styles.panel}><h2 style={styles.h2}>Management actions</h2><ul style={styles.list}><li>Prioritise open shifts at accounts below 92% fulfilment.</li><li>Review low-margin shifts before extending or adding incentives.</li><li>Resolve payroll-affecting attendance exceptions before export.</li></ul></section>
        <section style={styles.panel}><h2 style={styles.h2}>Data controls</h2><ul style={styles.list}><li>No worker-level PII in aggregate reporting.</li><li>Client/site access should be constrained by role and assignment.</li><li>Downloads and approval actions must be audited server-side.</li></ul></section>
      </div>
    </section>
  );
}

const styles: Record<string, any> = {
  page: { padding: '32px 24px 48px', maxWidth: 1500, margin: '0 auto' },
  headingRow: { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 20, flexWrap: 'wrap', marginBottom: 22 },
  eyebrow: { color: '#a7b5ff', fontSize: 12, letterSpacing: 1.3, fontWeight: 800 },
  h1: { fontSize: 32, margin: '6px 0 8px', letterSpacing: '-0.03em' },
  h2: { fontSize: 18, margin: 0 },
  sub: { color: '#b7bec9', margin: 0, maxWidth: 760, lineHeight: 1.55 },
  period: { border: '1px solid #353535', borderRadius: 999, padding: '9px 12px', color: '#c9ced6', fontSize: 13 },
  kpiGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))', gap: 14, marginBottom: 16 },
  card: { border: '1px solid #2b2b2b', borderRadius: 16, padding: 18, background: '#121212' },
  label: { color: '#a5adb9', fontSize: 13 }, value: { fontSize: 28, fontWeight: 800, marginTop: 7 }, note: { color: '#8f98a6', fontSize: 12, marginTop: 5 },
  panel: { border: '1px solid #2b2b2b', borderRadius: 16, padding: 20, background: '#121212', minWidth: 0 },
  panelHeader: { display: 'flex', justifyContent: 'space-between', gap: 14, alignItems: 'flex-start', flexWrap: 'wrap', marginBottom: 16 },
  legend: { color: '#929aa6', fontSize: 12, display: 'flex', alignItems: 'center', gap: 7 }, dotOk: { width: 7, height: 7, borderRadius: 99, background: '#32d583' }, dotWatch: { width: 7, height: 7, borderRadius: 99, background: '#fdb022' }, dotRisk: { width: 7, height: 7, borderRadius: 99, background: '#f97066' },
  table: { width: '100%', borderCollapse: 'collapse', fontSize: 13 }, th: { textAlign: 'left', color: '#8f98a6', padding: '10px 8px', borderBottom: '1px solid #303030', whiteSpace: 'nowrap' }, td: { padding: '13px 8px', borderBottom: '1px solid #242424', color: '#c9ced6', whiteSpace: 'nowrap' }, tdStrong: { padding: '13px 8px', borderBottom: '1px solid #242424', color: '#f4f4f5', fontWeight: 700, whiteSpace: 'nowrap' },
  pillOk: { color: '#6ce9a6', background: '#073d2b', padding: '4px 8px', borderRadius: 999, fontWeight: 700 }, pillWatch: { color: '#fec84b', background: '#4e3b06', padding: '4px 8px', borderRadius: 999, fontWeight: 700 }, pillRisk: { color: '#fda29b', background: '#4d1d1d', padding: '4px 8px', borderRadius: 999, fontWeight: 700 },
  twoCol: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 16, marginTop: 16 }, list: { color: '#bcc3cd', lineHeight: 1.7, paddingLeft: 20, marginBottom: 0 },
};
