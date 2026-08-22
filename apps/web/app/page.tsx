const industries = ['Hospitality', 'F&B', 'Cleaning', 'Retail', 'Promoters', 'Events'];

export default function HomePage() {
  return (
    <main style={{fontFamily:'Arial, sans-serif', background:'#0a0a0a', color:'#fff', minHeight:'100vh'}}>
      <section style={{maxWidth:1180, margin:'0 auto', padding:'96px 24px 64px'}}>
        <p style={{letterSpacing:3, color:'#aaa', fontSize:12}}>QY WORKFORCE</p>
        <h1 style={{fontSize:'clamp(42px,7vw,82px)', lineHeight:0.98, margin:'18px 0 24px', maxWidth:900}}>Flexible manpower. Verified workers. Better operations.</h1>
        <p style={{fontSize:20, lineHeight:1.5, maxWidth:720, color:'#ccc'}}>A workforce platform for employers who need reliable casual manpower and workers who want flexible shifts with clear expectations.</p>
        <div style={{display:'flex', gap:12, flexWrap:'wrap', marginTop:32}}>
          <a href="/employers" data-analytics-event="home_hire_workers" style={{background:'#fff', color:'#000', padding:'15px 22px', borderRadius:10, textDecoration:'none', fontWeight:700}}>Hire workers</a>
          <a href="/workers" data-analytics-event="home_find_shifts" style={{border:'1px solid #444', color:'#fff', padding:'15px 22px', borderRadius:10, textDecoration:'none', fontWeight:700}}>Find shifts</a>
          <a href="/how-it-works" data-analytics-event="home_how_it_works" style={{border:'1px solid #333', color:'#ccc', padding:'15px 22px', borderRadius:10, textDecoration:'none'}}>How it works</a>
        </div>
      </section>

      <section style={{maxWidth:1180, margin:'0 auto', padding:'32px 24px 80px'}}>
        <p style={{color:'#888'}}>Industries</p>
        <div style={{display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(160px,1fr))', gap:12}}>
          {industries.map(x => <div key={x} style={{border:'1px solid #222', borderRadius:14, padding:22, background:'#111'}}><strong>{x}</strong></div>)}
        </div>
      </section>

      <section id="employers" style={{maxWidth:1180, margin:'0 auto', padding:'72px 24px', display:'grid', gap:28}}>
        <h2 style={{fontSize:42, margin:0}}>Built for employers who need fulfilment, not spreadsheets.</h2>
        <p style={{fontSize:18, lineHeight:1.6, color:'#bbb', maxWidth:760}}>Create shifts, match verified workers, monitor attendance, approve timesheets and track labour margin from one operations view.</p>
        <a href="/employers" data-analytics-event="home_employer_journey" style={{color:'#fff',fontWeight:700}}>Request manpower →</a>
      </section>

      <section id="workers" style={{maxWidth:1180, margin:'0 auto', padding:'72px 24px 56px'}}>
        <h2 style={{fontSize:42, marginBottom:16}}>One profile. More ways to work.</h2>
        <p style={{fontSize:18, lineHeight:1.6, color:'#bbb', maxWidth:760}}>Complete verification and training once, then access shifts you are qualified for across hospitality, F&B, cleaning, retail, promotions and events.</p>
        <a href="/workers" data-analytics-event="home_worker_journey" style={{color:'#fff',fontWeight:700}}>Register interest →</a>
      </section>

      <section style={{maxWidth:1180, margin:'0 auto', padding:'24px 24px 80px'}}>
        <div style={{display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(220px,1fr))', gap:14}}>
          <article style={{border:'1px solid #222', borderRadius:16, padding:24, background:'#111'}}><strong>Verified readiness</strong><p style={{color:'#aaa', lineHeight:1.55}}>Identity, work eligibility, training and deployability are kept as separate controlled states.</p></article>
          <article style={{border:'1px solid #222', borderRadius:16, padding:24, background:'#111'}}><strong>Attendance integrity</strong><p style={{color:'#aaa', lineHeight:1.55}}>Server-side assignment, timing and geofence checks protect clock-in and clock-out records.</p></article>
          <article style={{border:'1px solid #222', borderRadius:16, padding:24, background:'#111'}}><strong>Privacy-conscious operations</strong><p style={{color:'#aaa', lineHeight:1.55}}>Role-based access, audit trails and minimised operational data exposure are designed in from the start.</p></article>
        </div>
        <a href="/trust" data-analytics-event="home_trust" style={{display:'inline-block', color:'#fff', fontWeight:700, marginTop:20}}>See trust & compliance approach →</a>
      </section>

      <footer style={{maxWidth:1180,margin:'0 auto',padding:'28px 24px 44px',borderTop:'1px solid #222',display:'flex',gap:18,flexWrap:'wrap',fontSize:14}}>
        <a href="/trust" style={{color:'#aaa'}}>Trust & Compliance</a><a href="/privacy" style={{color:'#aaa'}}>Privacy</a><a href="/terms" style={{color:'#aaa'}}>Terms</a>
      </footer>
    </main>
  );
}