'use client';

import { FormEvent, useState } from 'react';

export default function EmployersPage() {
  const [state, setState] = useState<'idle'|'sending'|'done'|'error'>('idle');

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setState('sending');
    const form = new FormData(e.currentTarget);
    const manpowerRequest = String(form.get('manpowerRequest') || '').trim();
    const payload = {
      type: 'employer',
      companyName: form.get('companyName'),
      contactName: form.get('contactName'),
      email: form.get('email'),
      phone: form.get('phone'),
      deploymentTimeline: 'To be confirmed',
      rolesHeadcount: manpowerRequest,
      location: 'To be confirmed',
      requirements: manpowerRequest,
      source: 'meta_employer_ad',
      campaign: 'qy_workforce_employer_leads',
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
    } catch {
      setState('error');
    }
  }

  return <main style={{maxWidth:760,margin:'0 auto',padding:'64px 24px',fontFamily:'Arial,sans-serif'}}>
    <p style={{letterSpacing:3,fontSize:12,fontWeight:700}}>QY WORKFORCE FOR EMPLOYERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,64px)',margin:'12px 0 16px'}}>Need staff urgently?</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#444',maxWidth:650}}>Tell us what manpower you need. We will review your request and, if you opt in, our AI sales assistant may follow up on WhatsApp to clarify the requirement before handing a qualified lead to our team.</p>
    {state==='done' ? <div style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Request received.</strong><p>Our team will review your manpower requirement. If you opted in to WhatsApp follow-up, our qualification assistant may contact you first to clarify the details.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <input required name="contactName" placeholder="Name" maxLength={120} style={field}/>
      <input required name="companyName" placeholder="Company" maxLength={160} style={field}/>
      <input required type="email" name="email" placeholder="Email" maxLength={254} style={field}/>
      <input required type="tel" name="phone" placeholder="Contact number" maxLength={32} style={field}/>
      <textarea required name="manpowerRequest" placeholder="Tell us your manpower request — e.g. role, number of staff, location, shift hours and when you need them." maxLength={1000} rows={7} style={field}/>
      <label style={consentStyle}><input required type="checkbox" name="pdpaConsent"/> <span>I consent to QY Workforce using these details to respond to and manage this manpower enquiry, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <label style={consentStyle}><input type="checkbox" name="whatsappConsent"/> <span>I agree to be contacted on WhatsApp about this enquiry, including by an automated qualification assistant. I can ask to stop messages at any time.</span></label>
      <button disabled={state==='sending'} style={buttonStyle}>{state==='sending'?'Submitting…':'Request Workers'}</button>
      {state==='error' && <p role="alert">We could not submit this enquiry. Please check the required fields and try again.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
const consentStyle = {display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5};
const buttonStyle = {padding:'16px 20px',border:0,borderRadius:10,background:'#0b1f33',color:'#fff',fontWeight:700,fontSize:16};
