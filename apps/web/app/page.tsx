import Link from 'next/link';
import { ConsentBanner, SiteFooter, SiteHeader } from './components/site-shell';

const industries = [
  { name: 'Hospitality', icon: '✦', copy: 'Banquet, service crew & hotel operations' },
  { name: 'F&B', icon: '◉', copy: 'Service, kitchen support & peak-hour crews' },
  { name: 'Cleaning', icon: '✧', copy: 'Room, public-area & commercial cleaning' },
  { name: 'Retail', icon: '□', copy: 'Store support, stock handling & customer service' },
  { name: 'Promotions', icon: '↗', copy: 'Brand ambassadors & roadshow promoters' },
  { name: 'Events', icon: '◆', copy: 'Event crew, ushers & on-ground support' },
];

const steps = [
  ['01', 'Register once', 'Tell us your work interests, availability and preferred locations.'],
  ['02', 'Get verified', 'Complete onboarding and role checks before being matched to suitable work.'],
  ['03', 'Pick suitable shifts', 'Choose opportunities that fit your schedule and role profile.'],
  ['04', 'Clock in & get paid', 'Attendance and approved timesheets support a clearer payout workflow.'],
];

export default function HomePage() {
  return (
    <main style={{ background:'#fff', minHeight:'100vh', color:'#101828' }}>
      <SiteHeader />

      <section style={{position:'relative', overflow:'hidden', background:'linear-gradient(135deg,#07111f 0%,#102744 55%,#0f766e 140%)', color:'#fff'}}>
        <div style={{position:'absolute', inset:0, background:'radial-gradient(circle at 75% 25%,rgba(45,212,191,.18),transparent 30%),radial-gradient(circle at 15% 90%,rgba(96,165,250,.16),transparent 28%)'}} />
        <div style={{position:'relative', maxWidth:1180, margin:'0 auto', padding:'clamp(54px,8vw,96px) 24px 70px', display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(310px,1fr))', gap:44, alignItems:'center'}}>
          <div>
            <div style={{display:'inline-flex',alignItems:'center',gap:8,padding:'7px 12px',border:'1px solid rgba(255,255,255,.18)',borderRadius:999,background:'rgba(255,255,255,.07)',fontSize:12,fontWeight:800,letterSpacing:1.5}}>FLEXIBLE WORK • SINGAPORE</div>
            <h1 style={{fontSize:'clamp(44px,6.7vw,78px)', letterSpacing:'-.055em', lineHeight:.98, margin:'22px 0 22px', maxWidth:720}}>Work when it works for you.</h1>
            <p style={{fontSize:'clamp(18px,2vw,21px)', lineHeight:1.55, maxWidth:650, color:'#DCE7F4'}}>Flexible casual work across hospitality, F&amp;B, cleaning, retail, promotions and events — with clearer onboarding, shift tracking and attendance.</p>
            <div style={{display:'flex', gap:12, flexWrap:'wrap', marginTop:30}}>
              <Link href="/workers" style={{background:'#2DD4BF', color:'#052E2B', padding:'16px 22px', borderRadius:12, textDecoration:'none', fontWeight:850, boxShadow:'0 10px 30px rgba(45,212,191,.22)'}}>Register as a casual worker →</Link>
              <Link href="/employers" style={{border:'1px solid rgba(255,255,255,.28)', background:'rgba(255,255,255,.06)', color:'#fff', padding:'16px 22px', borderRadius:12, textDecoration:'none', fontWeight:750}}>I need workers</Link>
            </div>
            <div style={{display:'flex',gap:22,flexWrap:'wrap',marginTop:28,color:'#C8D6E5',fontSize:13}}>
              <span>✓ One registration</span><span>✓ Multiple job types</span><span>✓ Clearer attendance workflow</span>
            </div>
          </div>

          <div aria-label="QY Workforce flexible work visual" style={{position:'relative',minHeight:470}}>
            <div style={{position:'absolute',inset:'20px 0 0 30px',borderRadius:28,overflow:'hidden',boxShadow:'0 30px 80px rgba(0,0,0,.35)',border:'1px solid rgba(255,255,255,.14)',background:'#14263a'}}>
              <img src="https://images.unsplash.com/photo-1521737711867-e3b97375f902?auto=format&fit=crop&w=1100&q=82" alt="People working together" style={{width:'100%',height:'100%',objectFit:'cover',display:'block',opacity:.78}} />
              <div style={{position:'absolute',inset:0,background:'linear-gradient(180deg,transparent 38%,rgba(4,18,31,.92) 100%)'}} />
              <div style={{position:'absolute',left:24,right:24,bottom:24}}>
                <div style={{fontSize:13,color:'#99F6E4',fontWeight:800,letterSpacing:1.2}}>QY WORKFORCE</div>
                <div style={{fontSize:28,fontWeight:850,marginTop:4}}>More ways to earn. One profile.</div>
              </div>
            </div>
            <div style={{position:'absolute',top:0,right:0,background:'#fff',color:'#101828',padding:'14px 16px',borderRadius:16,boxShadow:'0 16px 40px rgba(0,0,0,.24)',maxWidth:185}}><div style={{fontSize:12,color:'#667085'}}>SHIFT TYPES</div><strong style={{fontSize:18}}>Hospitality · F&amp;B · Events</strong></div>
            <div style={{position:'absolute',left:0,bottom:24,background:'#2DD4BF',color:'#052E2B',padding:'15px 17px',borderRadius:16,boxShadow:'0 16px 40px rgba(0,0,0,.2)',maxWidth:205}}><strong style={{fontSize:18}}>Casual worker sign-up</strong><div style={{fontSize:13,marginTop:4}}>Register your interest in minutes.</div></div>
          </div>
        </div>
      </section>

      <section style={{maxWidth:1180, margin:'0 auto', padding:'78px 24px 60px'}}>
        <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(250px,1fr))',gap:28,alignItems:'end',marginBottom:30}}>
          <div><p style={{color:'#0F766E',fontSize:12,fontWeight:850,letterSpacing:1.6,marginBottom:10}}>OPPORTUNITIES ACROSS INDUSTRIES</p><h2 style={{fontSize:'clamp(34px,4.5vw,52px)',letterSpacing:'-.04em',lineHeight:1.03,margin:0}}>Find work that fits your schedule.</h2></div>
          <p style={{fontSize:17,lineHeight:1.65,color:'#475467',margin:0,maxWidth:520}}>From one-off event shifts to recurring hospitality and cleaning assignments, QY Workforce is being built around flexible work and clearer operations.</p>
        </div>
        <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(220px,1fr))',gap:14}}>
          {industries.map((x,i) => <div key={x.name} style={{border:'1px solid #E5E7EB',borderRadius:18,padding:22,background:i===0?'#F0FDFA':'#fff',minHeight:150,boxShadow:'0 8px 24px rgba(16,24,40,.04)'}}><div style={{fontSize:25,color:'#0F766E',marginBottom:20}}>{x.icon}</div><strong style={{fontSize:19}}>{x.name}</strong><p style={{fontSize:14,lineHeight:1.5,color:'#667085',margin:'8px 0 0'}}>{x.copy}</p></div>)}
        </div>
      </section>

      <section style={{background:'#F8FAFC',borderTop:'1px solid #EEF2F6',borderBottom:'1px solid #EEF2F6'}}>
        <div style={{maxWidth:1180,margin:'0 auto',padding:'72px 24px',display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(300px,1fr))',gap:44,alignItems:'center'}}>
          <div style={{borderRadius:24,overflow:'hidden',minHeight:390,position:'relative',boxShadow:'0 20px 50px rgba(16,24,40,.12)'}}>
            <img src="https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1100&q=82" alt="Hospitality workplace" style={{position:'absolute',inset:0,width:'100%',height:'100%',objectFit:'cover'}} />
            <div style={{position:'absolute',inset:0,background:'linear-gradient(180deg,rgba(3,22,35,.02),rgba(3,22,35,.84))'}} />
            <div style={{position:'absolute',left:24,right:24,bottom:22,color:'#fff'}}><div style={{fontSize:12,fontWeight:800,letterSpacing:1.5,color:'#99F6E4'}}>FOR WORKERS</div><div style={{fontSize:30,fontWeight:850,marginTop:5}}>One profile. More ways to work.</div></div>
          </div>
          <div>
            <p style={{color:'#0F766E',fontWeight:850,fontSize:12,letterSpacing:1.6}}>HOW IT WORKS</p>
            <h2 style={{fontSize:'clamp(34px,4.4vw,50px)',letterSpacing:'-.04em',lineHeight:1.05,margin:'10px 0 24px'}}>Simple from sign-up to shift.</h2>
            <div style={{display:'grid',gap:16}}>{steps.map(([n,title,copy])=><div key={n} style={{display:'grid',gridTemplateColumns:'46px 1fr',gap:14,alignItems:'start'}}><div style={{width:42,height:42,borderRadius:12,display:'grid',placeItems:'center',background:'#CCFBF1',color:'#115E59',fontWeight:850}}>{n}</div><div><strong style={{fontSize:17}}>{title}</strong><p style={{margin:'5px 0 0',color:'#667085',lineHeight:1.55,fontSize:14}}>{copy}</p></div></div>)}</div>
            <Link href="/workers" style={{display:'inline-block',marginTop:28,background:'#101828',color:'#fff',padding:'15px 20px',borderRadius:11,textDecoration:'none',fontWeight:800}}>Register interest to work →</Link>
          </div>
        </div>
      </section>

      <section style={{maxWidth:1180,margin:'0 auto',padding:'76px 24px'}}>
        <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(300px,1fr))',gap:18}}>
          <div style={{padding:30,borderRadius:22,background:'#101828',color:'#fff'}}><div style={{fontSize:12,fontWeight:800,letterSpacing:1.5,color:'#99F6E4'}}>FOR EMPLOYERS</div><h2 style={{fontSize:34,lineHeight:1.06,letterSpacing:'-.035em',margin:'12px 0'}}>Need reliable flexible manpower?</h2><p style={{color:'#D0D5DD',lineHeight:1.6}}>Share your role, timing and site requirements. We support matching, attendance and timesheet visibility for operational teams.</p><Link href="/employers" style={{display:'inline-block',marginTop:12,color:'#fff',fontWeight:800}}>Request manpower →</Link></div>
          <div style={{padding:30,borderRadius:22,background:'#ECFDF3',border:'1px solid #D1FADF'}}><div style={{fontSize:12,fontWeight:800,letterSpacing:1.5,color:'#067647'}}>READY TO WORK?</div><h2 style={{fontSize:34,lineHeight:1.06,letterSpacing:'-.035em',margin:'12px 0'}}>Your next shift can start here.</h2><p style={{color:'#475467',lineHeight:1.6}}>Register once for casual work opportunities across multiple industries. Eligibility and onboarding checks apply before deployment.</p><Link href="/workers" style={{display:'inline-block',marginTop:12,color:'#065F46',fontWeight:850}}>Register as a casual worker →</Link></div>
        </div>
      </section>

      <SiteFooter />
      <ConsentBanner />
    </main>
  );
}
