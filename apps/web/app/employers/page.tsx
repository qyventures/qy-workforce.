'use client';

import { FormEvent, useState } from 'react';
import { ConsentBanner, SiteFooter, SiteHeader, trackConversion } from '../components/site-shell';

export default function EmployersPage() {
  const [state, setState] = useState<'idle'|'sending'|'done'|'error'>('idle');

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setState('sending');
    trackConversion('employer_lead_submit_attempt');
    const form = new FormData(e.currentTarget);
    const payload = {
      type: 'employer',
      companyName: form.get('companyName'),
      contactName: form.get('contactName'),
      email: form.get('email'),
      phone: form.get('phone'),
      deploymentTimeline: form.get('deploymentTimeline'),
      rolesHeadcount: form.get('rolesHeadcount'),
      location: form.get('location'),
      requirements: form.get('requirements'),
      source: 'website_employer',
      campaign: 'meta_employer_flexible_worker_preview',
      website: form.get('website'),
      pdpaConsent: form.get('pdpaConsent') === 'on',
      whatsappConsent: form.get('whatsappConsent') === 'on',
    };
    try {
      const res = await fetch('/api/leads', {
        method:'POST',
        headers:{'content-type':'application/json'},
        body:JSON.stringify(payload),
      });
      setState(res.ok ? 'done' : 'error');
      if (res.ok) trackConversion('employer_lead_submit_success');
    } catch {
      setState('error');
    }
  }

  return <main style={{minHeight:'100vh',background:'#F9FAFB'}}>
    <SiteHeader />
    <section style={{maxWidth:1120,margin:'0 auto',padding:'clamp(42px,7vw,76px) 24px',display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(min(100%, 320px),1fr))',gap:52,alignItems:'start'}}>
      <div><p style={eyebrow}>QY WORKFORCE FOR EMPLOYERS</p><h1 style={{fontSize:'clamp(40px,6vw,66px)',letterSpacing:'-.05em',lineHeight:1.02,margin:'14px 0 18px'}}>Staffing support for the shifts that cannot wait.</h1><p style={{fontSize:18,lineHeight:1.65,color:'#475467',maxWidth:530}}>Tell us the role, site, headcount and timing. We’ll review your request and follow up to clarify the operational details—there is no commitment from this form.</p><div style={{marginTop:30,display:'grid',gap:14}}>{['Share your requirements in a few minutes','Discuss deployment details before any booking','Keep a clear record of site and shift expectations'].map((item) => <div key={item} style={{display:'flex',gap:10,color:'#344054'}}><span aria-hidden="true" style={{color:'#0A0A0A',fontWeight:900}}>✓</span>{item}</div>)}</div><p style={{marginTop:34,fontSize:14,lineHeight:1.55,color:'#667085'}}>Please do not include NRIC, bank, health, or other sensitive personal information in this form.</p></div>
      <div style={card}>{state==='done' ? <div aria-live="polite"><strong style={{fontSize:21}}>Enquiry received.</strong><p style={{lineHeight:1.6,color:'#475467'}}>We’ll review the information you shared. If you opted in to WhatsApp follow-up, our qualification assistant may contact you to clarify the requirement before BD handoff.</p></div> : <><h2 style={{margin:'0 0 6px',fontSize:24}}>Request manpower</h2><p style={{margin:'0 0 22px',color:'#667085',lineHeight:1.55,fontSize:14}}>Fields marked required are needed to respond to your enquiry.</p>
    <form onSubmit={submit} style={{display:'grid',gap:14}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <label style={labelStyle}>Your name<input required name="contactName" autoComplete="name" maxLength={120} style={field}/></label>
      <label style={labelStyle}>Company<input required name="companyName" autoComplete="organization" maxLength={160} style={field}/></label>
      <div style={twoColumns}><label style={labelStyle}>Contact number<input required type="tel" name="phone" autoComplete="tel" inputMode="tel" maxLength={32} style={field}/></label><label style={labelStyle}>Work email<input required type="email" name="email" autoComplete="email" maxLength={254} style={field}/></label></div>
      <label style={labelStyle}>When do you need workers?<input required name="deploymentTimeline" placeholder="e.g. next week / 10 Sep" maxLength={160} style={field}/></label>
      <label style={labelStyle}>Roles and headcount<textarea required name="rolesHeadcount" maxLength={500} rows={3} style={field}/></label>
      <label style={labelStyle}>Deployment location(s)<input required name="location" maxLength={300} style={field}/></label>
      <label style={labelStyle}>Other requirements <span style={{fontWeight:400}}>(optional)</span><textarea name="requirements" placeholder="Shift hours, certifications or other notes" maxLength={1000} rows={4} style={field}/></label>
      <label style={consentStyle}><input required type="checkbox" name="pdpaConsent"/> <span>I consent to QY Workforce using these details to respond to and manage this manpower enquiry, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <label style={consentStyle}><input type="checkbox" name="whatsappConsent"/> <span>I agree to be contacted on WhatsApp about this enquiry, including by an automated qualification assistant. I can ask to stop messages at any time.</span></label>
      <button disabled={state==='sending'} style={buttonStyle}>{state==='sending'?'Submitting…':'Request flexible workers'}</button>
      {state==='error' && <p role="alert" style={{color:'#B42318',margin:0}}>We could not submit this enquiry. Please check the required fields and try again.</p>}
    </form></>}</div>
    </section><SiteFooter /><ConsentBanner />
  </main>;
}

const eyebrow = {letterSpacing:1.8,fontSize:12,fontWeight:800,color:'#475467'};
const card = {background:'#fff',border:'1px solid #EAECF0',borderRadius:18,padding:'clamp(20px,4vw,32px)',boxShadow:'0 8px 24px rgba(16,24,40,.05)'};
const field = {marginTop:6,padding:'12px 13px',border:'1px solid #98A2B3',borderRadius:9,fontSize:16,width:'100%',boxSizing:'border-box' as const,fontFamily:'inherit',background:'#fff'};
const labelStyle = {display:'grid',fontWeight:700,fontSize:14,color:'#344054'};
const twoColumns = {display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(190px,1fr))',gap:14};
const consentStyle = {display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5,fontSize:13,color:'#475467'};
const buttonStyle = {padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16};
