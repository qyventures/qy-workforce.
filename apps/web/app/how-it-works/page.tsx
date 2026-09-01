import type { Metadata } from 'next';
import Link from 'next/link';
import { ConsentBanner, SiteFooter, SiteHeader } from '../components/site-shell';

export const metadata: Metadata = {
  title: 'How it works | QY Workforce',
  description: 'See how QY Workforce connects staffing requirements, worker readiness, attendance and timesheet approval.',
  alternates: { canonical: '/how-it-works' },
};

const steps = [
  ['1','Tell us what you need','Employers define role, site, timing, headcount and required training.'],
  ['2','Match verified workers','Eligible workers see suitable shifts based on role, availability and deployment readiness.'],
  ['3','Run the shift','Workers accept, clock in at the site geofence and supervisors manage exceptions.'],
  ['4','Approve and reconcile','Timesheets move through approval into payroll-ready records and client reporting.'],
];

export default function HowItWorks() {
  return <main style={{minHeight:'100vh',background:'#0B1220',color:'#fff'}}><SiteHeader />
    <section style={{maxWidth:1050,margin:'0 auto',padding:'72px 24px'}}>
      <div style={{marginTop:42,color:'#8EA2FF',fontWeight:800,fontSize:12,letterSpacing:1.4}}>HOW IT WORKS</div>
      <h1 style={{fontSize:'clamp(38px,6vw,72px)',lineHeight:1.02,letterSpacing:'-.045em',maxWidth:850,margin:'10px 0 18px'}}>Flexible staffing with operational control built in.</h1>
      <p style={{color:'#B9C2D0',fontSize:18,lineHeight:1.6,maxWidth:720}}>A single workflow for worker readiness, matching, attendance, approvals and payroll handoff.</p>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(220px,1fr))',gap:14,marginTop:46}}>
        {steps.map(([n,t,d])=><article key={n} style={{border:'1px solid #27344A',borderRadius:18,padding:22,background:'#111B2D'}}><div style={{color:'#8EA2FF',fontWeight:900}}>{n}</div><h2 style={{fontSize:19,margin:'24px 0 9px'}}>{t}</h2><p style={{color:'#AAB5C6',lineHeight:1.55,fontSize:14,margin:0}}>{d}</p></article>)}
      </div>
      <div style={{display:'flex',gap:12,flexWrap:'wrap',marginTop:38}}><Link href="/employers" style={{background:'#fff',color:'#111827',padding:'13px 18px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Hire workers</Link><Link href="/workers" style={{border:'1px solid #3C4A61',color:'#fff',padding:'13px 18px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Find shifts</Link></div>
    </section><SiteFooter /><ConsentBanner />
  </main>
}
