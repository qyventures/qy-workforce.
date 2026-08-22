import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Trust & Compliance | QY Workforce',
  description: 'How QY Workforce approaches worker verification, attendance integrity, privacy, access control and operational auditability.',
};

const controls = [
  ['Worker readiness', 'Identity, work-eligibility, training and role readiness are tracked as separate states. Workers only see shifts they are approved to perform.'],
  ['Attendance integrity', 'Clock-in and clock-out use server-validated assignment, timing and site geofence controls. Suspicious or exceptional events are routed for review.'],
  ['Least privilege', 'Worker, supervisor, operations, finance and administrator permissions are separated. Sensitive actions are handled through role-checked server functions.'],
  ['Auditability', 'Key onboarding, attendance, timesheet, payroll and administrative decisions are recorded so operational changes can be traced and reviewed.'],
  ['Privacy by design', 'The platform is designed to minimise unnecessary personal data exposure. Operational views favour worker aliases and aggregated reporting where identity is not required.'],
  ['Retention controls', 'Personal and payroll information is subject to defined retention and deletion controls rather than indefinite storage.'],
];

export default function TrustPage() {
  return (
    <main style={{fontFamily:'Arial, sans-serif', background:'#0a0a0a', color:'#fff', minHeight:'100vh'}}>
      <section style={{maxWidth:1040, margin:'0 auto', padding:'88px 24px 44px'}}>
        <p style={{letterSpacing:3, color:'#999', fontSize:12}}>TRUST & COMPLIANCE</p>
        <h1 style={{fontSize:'clamp(38px,6vw,68px)', lineHeight:1.02, margin:'16px 0 22px', maxWidth:900}}>Workforce operations built with verification, privacy and accountability in mind.</h1>
        <p style={{fontSize:19, lineHeight:1.6, color:'#c7c7c7', maxWidth:800}}>QY Workforce is being designed around PDPA-conscious data handling, controlled access and operational evidence. The goal is simple: employers should know who is ready to work, workers should understand how their data is used, and sensitive actions should be reviewable.</p>
      </section>

      <section style={{maxWidth:1040, margin:'0 auto', padding:'28px 24px 72px'}}>
        <div style={{display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(260px,1fr))', gap:16}}>
          {controls.map(([title, body]) => (
            <article key={title} style={{border:'1px solid #242424', borderRadius:16, padding:24, background:'#111'}}>
              <h2 style={{fontSize:20, margin:'0 0 12px'}}>{title}</h2>
              <p style={{color:'#bdbdbd', lineHeight:1.6, margin:0}}>{body}</p>
            </article>
          ))}
        </div>
      </section>

      <section style={{maxWidth:1040, margin:'0 auto', padding:'8px 24px 72px'}}>
        <div style={{border:'1px solid #2b2b2b', borderRadius:18, padding:28, background:'#0f0f0f'}}>
          <h2 style={{fontSize:30, margin:'0 0 14px'}}>What this means for employers</h2>
          <p style={{color:'#bdbdbd', lineHeight:1.65, maxWidth:800}}>Shift fulfilment, attendance, timesheet review and payroll preparation are designed as one controlled workflow rather than disconnected spreadsheets and chat messages. Exceptions remain visible to authorised staff instead of being hidden by automation.</p>
          <a href="/employers" data-analytics-event="trust_employer_cta" style={{display:'inline-block', marginTop:12, background:'#fff', color:'#000', padding:'14px 20px', borderRadius:10, textDecoration:'none', fontWeight:700}}>Discuss your manpower needs</a>
        </div>
      </section>

      <section style={{maxWidth:1040, margin:'0 auto', padding:'0 24px 80px'}}>
        <h2 style={{fontSize:30, marginBottom:14}}>For workers</h2>
        <p style={{color:'#bdbdbd', lineHeight:1.65, maxWidth:800}}>We aim to collect only information needed for onboarding, eligibility, shift fulfilment, attendance, payment and compliance. Verification outcomes are separated from operational status, and production identity-provider access will only be enabled after the required approvals and controls are in place.</p>
        <div style={{display:'flex', gap:18, flexWrap:'wrap', marginTop:18}}>
          <a href="/privacy" style={{color:'#fff'}}>Read privacy notice →</a>
          <a href="/workers" data-analytics-event="trust_worker_cta" style={{color:'#fff'}}>Worker journey →</a>
        </div>
      </section>
    </main>
  );
}
