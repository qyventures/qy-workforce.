import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Industries | QY Workforce',
  description: 'Flexible staffing for hospitality, F&B, cleaning, retail, promotions and events with readiness, attendance and approval controls built in.',
};

const industries = [
  {
    id: 'hospitality',
    name: 'Hospitality',
    roles: ['Banquet crew', 'Housekeeping support', 'Stewarding', 'Service crew', 'Guest-facing support'],
    employer: 'Scale around occupancy, banquets and peak periods while keeping worker readiness and attendance visible.',
    worker: 'See hospitality shifts that match your approved role and training readiness.',
  },
  {
    id: 'food-beverage',
    name: 'Food & Beverage',
    roles: ['Service crew', 'Runners', 'Kitchen support', 'Cashier support', 'Peak-period crew'],
    employer: 'Add trained casual capacity for meal peaks, weekends and new-store demand without losing timesheet control.',
    worker: 'Access suitable service and kitchen-support shifts with clear site, timing and rate information.',
  },
  {
    id: 'cleaning',
    name: 'Cleaning',
    roles: ['Commercial cleaners', 'Hotel room support', 'Public-area cleaners', 'Turnaround crew'],
    employer: 'Plan site coverage around defined roles and readiness while supervisors retain exception and approval control.',
    worker: 'Build role readiness once, then see cleaning assignments you are eligible to accept.',
  },
  {
    id: 'retail',
    name: 'Retail',
    roles: ['Sales support', 'Replenishment', 'Queue management', 'Seasonal crew', 'Stock support'],
    employer: 'Respond to launches, campaigns and seasonal peaks with structured attendance and approved-hour reporting.',
    worker: 'Choose retail shifts that fit your role eligibility and availability.',
  },
  {
    id: 'promotions',
    name: 'Promotions & Roadshows',
    roles: ['Brand ambassadors', 'Promoters', 'Registration crew', 'Customer-acquisition support'],
    employer: 'Deploy campaign teams across sites with clearer fulfilment, attendance and approved-hour visibility.',
    worker: 'Discover event and roadshow opportunities with clear assignment details before accepting.',
  },
  {
    id: 'events',
    name: 'Events',
    roles: ['Ushers', 'Registration crew', 'Event crew', 'Logistics support', 'Venue operations'],
    employer: 'Staff short-duration and high-headcount events while keeping site, attendance and supervisor review structured.',
    worker: 'Find event shifts aligned to your approved roles and deployment readiness.',
  },
];

export default function Industries() {
  return (
    <main style={{minHeight:'100vh',background:'#F7F8FB',color:'#101828',padding:'64px 24px'}}>
      <section style={{maxWidth:1080,margin:'0 auto'}}>
        <a href="/" style={{color:'#344054',textDecoration:'none',fontWeight:800}}>QY Workforce</a>
        <div style={{marginTop:40,color:'#4D63FF',fontWeight:850,fontSize:12,letterSpacing:1.3}}>INDUSTRIES</div>
        <h1 style={{fontSize:'clamp(38px,6vw,68px)',lineHeight:1.04,letterSpacing:'-.045em',maxWidth:850,margin:'9px 0 16px'}}>Built for labour-intensive operations where fill rate matters.</h1>
        <p style={{fontSize:18,color:'#667085',lineHeight:1.6,maxWidth:760}}>QY Workforce helps employers source suitable casual workers while keeping readiness, attendance, approvals and margin visibility in one workflow.</p>

        <nav aria-label="Industry shortcuts" style={{display:'flex',gap:10,flexWrap:'wrap',marginTop:28}}>
          {industries.map((industry) => (
            <a key={industry.id} href={`#${industry.id}`} style={{background:'#fff',border:'1px solid #D0D5DD',color:'#344054',padding:'10px 13px',borderRadius:999,textDecoration:'none',fontWeight:700,fontSize:14}}>{industry.name}</a>
          ))}
        </nav>

        <div style={{display:'grid',gap:18,marginTop:40}}>
          {industries.map((industry) => (
            <article id={industry.id} key={industry.id} style={{background:'#fff',border:'1px solid #E4E7EC',borderRadius:20,padding:'clamp(22px,4vw,34px)',scrollMarginTop:24}}>
              <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(260px,1fr))',gap:26,alignItems:'start'}}>
                <div>
                  <p style={{margin:'0 0 8px',color:'#4D63FF',fontWeight:800,fontSize:12,letterSpacing:1}}>QY WORKFORCE</p>
                  <h2 style={{margin:'0 0 14px',fontSize:28}}>{industry.name}</h2>
                  <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
                    {industry.roles.map((role) => <span key={role} style={{background:'#F2F4F7',color:'#344054',padding:'7px 10px',borderRadius:999,fontSize:13}}>{role}</span>)}
                  </div>
                </div>
                <div style={{display:'grid',gap:14}}>
                  <div style={{borderLeft:'3px solid #4D63FF',paddingLeft:14}}><strong>For employers</strong><p style={{margin:'6px 0 0',color:'#667085',lineHeight:1.55,fontSize:14}}>{industry.employer}</p></div>
                  <div style={{borderLeft:'3px solid #98A2B3',paddingLeft:14}}><strong>For workers</strong><p style={{margin:'6px 0 0',color:'#667085',lineHeight:1.55,fontSize:14}}>{industry.worker}</p></div>
                </div>
              </div>
              <div style={{display:'flex',gap:12,flexWrap:'wrap',marginTop:24}}>
                <a href={`/employers?industry=${industry.id}`} data-analytics-event={`industry_${industry.id}_employer`} style={{background:'#111827',color:'#fff',padding:'12px 16px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Request manpower</a>
                <a href={`/workers?industry=${industry.id}`} data-analytics-event={`industry_${industry.id}_worker`} style={{border:'1px solid #D0D5DD',color:'#344054',padding:'12px 16px',borderRadius:10,textDecoration:'none',fontWeight:800}}>Find suitable shifts</a>
              </div>
            </article>
          ))}
        </div>

        <section style={{marginTop:34,background:'#101828',color:'#fff',borderRadius:20,padding:'clamp(24px,4vw,36px)'}}>
          <h2 style={{fontSize:30,margin:'0 0 10px'}}>One operating model across every sector.</h2>
          <p style={{color:'#D0D5DD',lineHeight:1.6,maxWidth:760,margin:'0 0 22px'}}>Worker readiness, shift acceptance, geofenced attendance, supervisor review and payroll-ready records stay consistent even when role requirements differ by industry.</p>
          <a href="/how-it-works" data-analytics-event="industries_how_it_works" style={{color:'#fff',fontWeight:800}}>See how the workflow works →</a>
        </section>
      </section>
    </main>
  );
}
