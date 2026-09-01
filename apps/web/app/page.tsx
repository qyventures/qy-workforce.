import Link from 'next/link';
import { ConsentBanner, ConversionLink, SiteFooter, SiteHeader } from './components/site-shell';

const industries = ['Hospitality', 'F&B', 'Cleaning', 'Retail', 'Promotions', 'Events'];

export default function HomePage() {
  return (
    <main style={{ background:'#fff', minHeight:'100vh' }}>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify({ '@context': 'https://schema.org', '@type': 'Organization', name: 'QY Workforce', url: 'https://qyworkforce.com', description: 'Flexible staffing for Singapore employers and workers.' }) }} />
      <SiteHeader />
      <section style={{background:'#0A0A0A', color:'#fff'}}><div style={{maxWidth:1180, margin:'0 auto', padding:'clamp(62px,10vw,112px) 24px 76px'}}>
        <p style={{letterSpacing:2.4, color:'#C7D0DE', fontSize:12, fontWeight:800}}>FLEXIBLE STAFFING IN SINGAPORE</p>
        <h1 style={{fontSize:'clamp(42px,7vw,82px)', letterSpacing:'-.055em', lineHeight:0.98, margin:'18px 0 24px', maxWidth:900}}>Flexible manpower. Clearer operations.</h1>
        <p style={{fontSize:20, lineHeight:1.5, maxWidth:720, color:'#D0D5DD'}}>For employers who need reliable casual manpower and workers looking for flexible shifts with clear expectations.</p>
        <div style={{display:'flex', gap:12, flexWrap:'wrap', marginTop:32}}>
          <ConversionLink href="/employers" event="home_employer_cta" style={{background:'#fff', color:'#000', padding:'15px 22px', borderRadius:10, textDecoration:'none', fontWeight:700}}>Hire workers</ConversionLink>
          <ConversionLink href="/workers" event="home_worker_cta" style={{border:'1px solid #667085', color:'#fff', padding:'15px 22px', borderRadius:10, textDecoration:'none', fontWeight:700}}>Find shifts</ConversionLink>
          <Link href="/how-it-works" style={{border:'1px solid #475467', color:'#EAECF0', padding:'15px 22px', borderRadius:10, textDecoration:'none'}}>How it works</Link>
        </div>
      </div></section>

      <section style={{maxWidth:1180, margin:'0 auto', padding:'72px 24px'}}>
        <p style={{color:'#475467', fontSize:13, fontWeight:800, letterSpacing:1.4}}>INDUSTRIES WE SUPPORT</p>
        <div style={{display:'grid', gridTemplateColumns:'repeat(auto-fit,minmax(160px,1fr))', gap:12}}>
          {industries.map(x => <div key={x} style={{border:'1px solid #EAECF0', borderRadius:14, padding:22, background:'#fff'}}><strong>{x}</strong></div>)}
        </div>
        <Link href="/industries" style={{display:'inline-block', marginTop:20, color:'#101828', fontWeight:750}}>Explore industries →</Link>
      </section>

      <section id="employers" style={{background:'#F9FAFB'}}><div style={{maxWidth:1180, margin:'0 auto', padding:'72px 24px', display:'grid', gap:20}}>
        <h2 style={{fontSize:42, margin:0}}>Built for employers who need fulfilment, not spreadsheets.</h2>
        <p style={{fontSize:18, lineHeight:1.6, color:'#475467', maxWidth:760}}>Share your role, timing and site requirements. Eligible workers can be matched to operational needs, with attendance and timesheet workflows designed for visibility.</p>
        <ConversionLink href="/employers" event="home_employer_detail_cta" style={{color:'#101828',fontWeight:750}}>Request manpower →</ConversionLink>
      </div></section>

      <section id="workers" style={{maxWidth:1180, margin:'0 auto', padding:'72px 24px 80px'}}>
        <h2 style={{fontSize:42, marginBottom:16}}>One profile. More ways to work.</h2>
        <p style={{fontSize:18, lineHeight:1.6, color:'#475467', maxWidth:760}}>Register interest in roles that suit you. Verification and onboarding are separate steps before any work opportunity is confirmed.</p>
        <ConversionLink href="/workers" event="home_worker_detail_cta" style={{color:'#101828',fontWeight:750}}>Register interest →</ConversionLink>
      </section>
      <SiteFooter />
      <ConsentBanner />
    </main>
  );
}
