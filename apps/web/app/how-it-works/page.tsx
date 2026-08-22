import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'How QY Workforce Works | Employers and Workers',
  description: 'See how QY Workforce connects verified workers with employer shifts through readiness checks, matching, geofenced attendance, approvals and payroll-ready records.',
};

const employerSteps = [
  ['01','Create demand','Define site, role, date, shift timing, headcount and commercial rates. Draft creation stays behind authorised Ops controls.'],
  ['02','Match ready workers','Only workers who meet current role, identity, work-eligibility, training, vetting and consent requirements can discover eligible shifts.'],
  ['03','Monitor fulfilment','Track accepted headcount, attendance status and exceptions without exposing unnecessary worker identity data.'],
  ['04','Approve and reconcile','Supervisors review submitted timesheets, exceptions are triaged, and approved records move toward payroll and client reporting.'],
];

const workerSteps = [
  ['01','Join once','Create a worker profile, choose work interests and complete the required readiness steps for the roles you want.'],
  ['02','See suitable shifts','Discover only open shifts that match your approved roles and current deployment readiness.'],
  ['03','Work with clear records','Accept a shift, view assignment details and clock in/out with server-validated site and timing checks.'],
  ['04','Track your pay status','Review submitted, approved or action-needed timesheets and see earnings visibility from the same worker journey.'],
];

const safeguards = [
  ['Readiness is live','Training expiry, withdrawn required consent or a new vetting issue can immediately remove shift eligibility.'],
  ['Attendance is server-authoritative','Assignment ownership, shift timing and geofence rules are checked on the backend rather than trusted to the phone alone.'],
  ['Approvals are auditable','Supervisor and Ops decisions use scoped server-side workflows with role checks and audit events.'],
  ['Privacy by design','Operational views use minimised or pseudonymous data where full worker identity is not needed.'],
];

function StepGrid({ steps }: { steps: string[][] }) {
  return (
    <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(220px,1fr))',gap:14,marginTop:28}}>
      {steps.map(([n,t,d]) => (
        <article key={n} style={{border:'1px solid #27344A',borderRadius:18,padding:22,background:'#111B2D',minWidth:0}}>
          <div style={{color:'#8EA2FF',fontWeight:900,fontSize:13,letterSpacing:1}}>{n}</div>
          <h3 style={{fontSize:20,margin:'22px 0 9px'}}>{t}</h3>
          <p style={{color:'#AAB5C6',lineHeight:1.6,fontSize:14,margin:0}}>{d}</p>
        </article>
      ))}
    </div>
  );
}

export default function HowItWorks() {
  return (
    <main style={{minHeight:'100vh',background:'#0B1220',color:'#fff',padding:'64px 24px 48px',fontFamily:'Inter, ui-sans-serif, system-ui, sans-serif'}}>
      <section style={{maxWidth:1120,margin:'0 auto'}}>
        <nav aria-label="Breadcrumb" style={{display:'flex',gap:10,alignItems:'center',flexWrap:'wrap',fontSize:14}}>
          <a href="/" style={{color:'#B9C2D0',textDecoration:'none'}}>QY Workforce</a>
          <span aria-hidden="true" style={{color:'#58677F'}}>›</span>
          <span style={{color:'#fff'}}>How it works</span>
        </nav>

        <div style={{marginTop:42,color:'#8EA2FF',fontWeight:800,fontSize:12,letterSpacing:1.4}}>HOW IT WORKS</div>
        <h1 style={{fontSize:'clamp(40px,6vw,72px)',lineHeight:1.02,letterSpacing:'-.045em',maxWidth:900,margin:'10px 0 18px'}}>From staffing request to approved timesheet, in one controlled workflow.</h1>
        <p style={{color:'#B9C2D0',fontSize:18,lineHeight:1.65,maxWidth:790}}>QY Workforce gives employers an operational path to fulfil casual shifts while giving workers a clear journey from readiness to earnings visibility.</p>
        <div style={{display:'flex',gap:12,flexWrap:'wrap',marginTop:30}}>
          <a href="/employers" data-analytics-event="how_employer_cta_top" style={{background:'#fff',color:'#111827',padding:'14px 20px',borderRadius:10,textDecoration:'none',fontWeight:800}}>I need workers</a>
          <a href="/workers" data-analytics-event="how_worker_cta_top" style={{border:'1px solid #3C4A61',color:'#fff',padding:'14px 20px',borderRadius:10,textDecoration:'none',fontWeight:800}}>I want shifts</a>
        </div>
      </section>

      <section id="employers" style={{maxWidth:1120,margin:'72px auto 0'}}>
        <div style={{color:'#7DD3FC',fontSize:12,fontWeight:800,letterSpacing:1.3}}>FOR EMPLOYERS</div>
        <h2 style={{fontSize:'clamp(30px,4vw,46px)',margin:'10px 0 0'}}>Turn demand into a controlled staffing workflow.</h2>
        <StepGrid steps={employerSteps} />
      </section>

      <section id="workers" style={{maxWidth:1120,margin:'72px auto 0'}}>
        <div style={{color:'#A7F3D0',fontSize:12,fontWeight:800,letterSpacing:1.3}}>FOR WORKERS</div>
        <h2 style={{fontSize:'clamp(30px,4vw,46px)',margin:'10px 0 0'}}>Know what you need, where you work and what happens next.</h2>
        <StepGrid steps={workerSteps} />
      </section>

      <section style={{maxWidth:1120,margin:'72px auto 0',borderTop:'1px solid #27344A',paddingTop:54}}>
        <div style={{display:'grid',gridTemplateColumns:'minmax(0,1.1fr) minmax(0,1.9fr)',gap:30,alignItems:'start'}}>
          <div style={{minWidth:0}}>
            <div style={{color:'#C4B5FD',fontSize:12,fontWeight:800,letterSpacing:1.3}}>CONTROL POINTS</div>
            <h2 style={{fontSize:'clamp(28px,4vw,42px)',lineHeight:1.08,margin:'10px 0 14px'}}>Designed for trust at the moments that matter.</h2>
            <p style={{color:'#AAB5C6',lineHeight:1.65,margin:0}}>The worker app and Ops console do not decide sensitive status changes independently. Critical eligibility, attendance and review actions remain server-controlled.</p>
          </div>
          <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(220px,1fr))',gap:12,minWidth:0}}>
            {safeguards.map(([title,desc]) => (
              <article key={title} style={{border:'1px solid #27344A',borderRadius:16,padding:20,background:'#0E1828'}}>
                <strong style={{display:'block',fontSize:16}}>{title}</strong>
                <p style={{color:'#AAB5C6',fontSize:14,lineHeight:1.6,margin:'9px 0 0'}}>{desc}</p>
              </article>
            ))}
          </div>
        </div>
        <a href="/trust" data-analytics-event="how_trust_cta" style={{display:'inline-block',marginTop:24,color:'#fff',fontWeight:800}}>See our trust & compliance approach →</a>
      </section>

      <section style={{maxWidth:1120,margin:'72px auto 0',padding:'34px',border:'1px solid #27344A',borderRadius:20,background:'#111B2D'}}>
        <h2 style={{fontSize:'clamp(28px,4vw,42px)',margin:'0 0 12px'}}>Choose your next step.</h2>
        <p style={{color:'#B9C2D0',fontSize:16,lineHeight:1.6,maxWidth:700,margin:'0 0 24px'}}>Employers can request manpower for upcoming demand. Workers can register interest and move through the readiness journey for suitable roles.</p>
        <div style={{display:'flex',gap:12,flexWrap:'wrap'}}>
          <a href="/employers" data-analytics-event="how_employer_cta_bottom" style={{background:'#fff',color:'#111827',padding:'14px 20px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Request manpower</a>
          <a href="/workers" data-analytics-event="how_worker_cta_bottom" style={{border:'1px solid #50607A',color:'#fff',padding:'14px 20px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Register as a worker</a>
        </div>
      </section>
    </main>
  );
}
