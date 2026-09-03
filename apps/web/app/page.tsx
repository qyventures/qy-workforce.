import Link from 'next/link';
import { ConsentBanner, ConversionLink, SiteFooter, SiteHeader } from './components/site-shell';

const industries = ['Hospitality', 'F&B', 'Cleaning', 'Retail', 'Promotions', 'Events'];
const faq = [
  ['Does an enquiry guarantee workers or a shift?', 'No. An enquiry starts a conversation. Employer requirements, worker eligibility, availability and final arrangements are confirmed separately.'],
  ['What information should I avoid sharing?', 'Do not include NRIC, bank, health or identity-document details in public forms. We will explain any later onboarding requirements through the appropriate process.'],
  ['Can I decline WhatsApp follow-up or analytics?', 'Yes. Both are optional. The website and enquiry forms remain available if you decline either choice.'],
];

export default function HomePage() {
  return (
    <main id="main-content" style={{ background:'#fff', minHeight:'100vh' }}>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify([
        { '@context': 'https://schema.org', '@type': 'Organization', name: 'QY Workforce', url: 'https://qyworkforce.com', description: 'Flexible staffing for Singapore employers and workers.' },
        { '@context': 'https://schema.org', '@type': 'WebSite', name: 'QY Workforce', url: 'https://qyworkforce.com', inLanguage: 'en-SG' },
        { '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: faq.map(([question, answer]) => ({ '@type': 'Question', name: question, acceptedAnswer: { '@type': 'Answer', text: answer } })) },
      ]) }} />
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

      <section aria-label="Pilot commitments" style={{borderBottom:'1px solid #EAECF0',background:'#fff'}}><div style={{maxWidth:1180,margin:'0 auto',padding:'18px 24px',display:'flex',gap:18,justifyContent:'space-between',flexWrap:'wrap',color:'#475467',fontSize:14}}>
        <span><strong style={{color:'#101828'}}>Pilot-ready by design</strong> · every request is reviewed before a booking</span>
        <span>Consent-led contact · no sensitive documents in public forms · optional anonymous analytics</span>
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

      <section aria-labelledby="journey-heading" style={{maxWidth:1180,margin:'0 auto',padding:'72px 24px'}}>
        <p style={{color:'#475467',fontSize:13,fontWeight:800,letterSpacing:1.4}}>START WITH THE RIGHT PATH</p>
        <h2 id="journey-heading" style={{fontSize:42,letterSpacing:'-.04em',margin:'12px 0 26px'}}>A clear next step for both sides.</h2>
        <div className="journey-grid">
          <article style={{border:'1px solid #EAECF0',borderRadius:16,padding:24,background:'#fff'}}><p style={{margin:'0 0 8px',fontWeight:800,color:'#667085',fontSize:13}}>FOR EMPLOYERS</p><h3 style={{margin:'0 0 10px',fontSize:23}}>Need people for a shift?</h3><p style={{color:'#475467',lineHeight:1.6,margin:'0 0 18px'}}>Share the site, timing and headcount. We’ll clarify requirements before discussing a deployment.</p><ConversionLink href="/employers" event="home_journey_employer" style={{color:'#101828',fontWeight:800}}>Request manpower →</ConversionLink></article>
          <article style={{border:'1px solid #EAECF0',borderRadius:16,padding:24,background:'#fff'}}><p style={{margin:'0 0 8px',fontWeight:800,color:'#667085',fontSize:13}}>FOR WORKERS</p><h3 style={{margin:'0 0 10px',fontSize:23}}>Looking for flexible work?</h3><p style={{color:'#475467',lineHeight:1.6,margin:'0 0 18px'}}>Tell us your interests, availability and preferred locations. Any opportunity is reviewed separately before acceptance.</p><ConversionLink href="/workers" event="home_journey_worker" style={{color:'#101828',fontWeight:800}}>Register interest →</ConversionLink></article>
        </div>
      </section>

      <section id="workers" style={{maxWidth:1180, margin:'0 auto', padding:'72px 24px 80px'}}>
        <h2 style={{fontSize:42, marginBottom:16}}>One profile. More ways to work.</h2>
        <p style={{fontSize:18, lineHeight:1.6, color:'#475467', maxWidth:760}}>Register interest in roles that suit you. Verification and onboarding are separate steps before any work opportunity is confirmed.</p>
        <ConversionLink href="/workers" event="home_worker_detail_cta" style={{color:'#101828',fontWeight:750}}>Register interest →</ConversionLink>
      </section>
      <section aria-labelledby="trust-heading" style={{background:'#F7F8FB',borderTop:'1px solid #EAECF0',borderBottom:'1px solid #EAECF0'}}><div style={{maxWidth:1180,margin:'0 auto',padding:'72px 24px'}}>
        <p style={{color:'#475467',fontSize:13,fontWeight:800,letterSpacing:1.4}}>READY FOR RESPONSIBLE PILOTS</p>
        <h2 id="trust-heading" style={{fontSize:42,letterSpacing:'-.04em',margin:'12px 0 16px'}}>Clarity for every side of the shift.</h2>
        <p style={{fontSize:18,lineHeight:1.6,color:'#475467',maxWidth:760}}>Worker readiness, site expectations, attendance and approvals are treated as operational records—not hidden assumptions.</p>
        <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(210px,1fr))',gap:14,marginTop:28}}>
          {['Consent-led enquiries','No sensitive documents on public forms','Attendance and timesheet visibility','Privacy-safe optional analytics'].map((item)=><div key={item} style={{background:'#fff',border:'1px solid #EAECF0',borderRadius:14,padding:20,fontWeight:750}}>{item}</div>)}
        </div>
        <Link href="/privacy" style={{display:'inline-block',marginTop:22,color:'#101828',fontWeight:750}}>Read our privacy approach →</Link>
      </div></section>
      <section aria-labelledby="faq-heading" style={{maxWidth:900,margin:'0 auto',padding:'72px 24px'}}>
        <h2 id="faq-heading" style={{fontSize:36,letterSpacing:'-.035em',margin:'0 0 24px'}}>Questions, answered.</h2>
        <div style={{display:'grid',gap:18}}>
          {faq.map(([question, answer]) => <details key={question} style={faqStyle}><summary style={summaryStyle}>{question}</summary><p style={answerStyle}>{answer}</p></details>)}
        </div>
      </section>
      <SiteFooter />
      <ConsentBanner />
    </main>
  );
}

const faqStyle = {borderTop:'1px solid #D0D5DD',padding:'18px 0'};
const summaryStyle = {cursor:'pointer',fontWeight:750,fontSize:17};
const answerStyle = {color:'#475467',lineHeight:1.6,maxWidth:720,margin:'12px 0 0'};
