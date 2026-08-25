'use client';

import { FormEvent, useState } from 'react';

export default function EmployersPage() {
  const [state, setState] = useState<'idle'|'sending'|'done'|'error'>('idle');

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setState('sending');
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
    } catch {
      setState('error');
    }
  }

  return <main style={{maxWidth:820,margin:'0 auto',padding:'72px 24px',fontFamily:'Arial,sans-serif'}}>
    <p style={{letterSpacing:3,fontSize:12}}>QY WORKFORCE FOR EMPLOYERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,68px)',marginBottom:16}}>Flexible workers when you need them.</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#444'}}>Tell us the roles, headcount and deployment timeline. With your permission, QY Workforce can follow up on WhatsApp to clarify the requirement before our BD team responds.</p>
    {state==='done' ? <div style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Enquiry received.</strong><p>If you opted in to WhatsApp follow-up, our qualification assistant may contact you to clarify your manpower requirements before BD handoff.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <input required name="contactName" placeholder="Your name" maxLength={120} style={field}/>
      <input required name="companyName" placeholder="Company" maxLength={160} style={field}/>
      <input required type="tel" name="phone" placeholder="Contact number" maxLength={32} style={field}/>
      <input required type="email" name="email" placeholder="Work email" maxLength={254} style={field}/>
      <input required name="deploymentTimeline" placeholder="When do you need workers? e.g. next week / 10 Sep" maxLength={160} style={field}/>
      <textarea required name="rolesHeadcount" placeholder="Roles and headcount needed" maxLength={500} rows={3} style={field}/>
      <input required name="location" placeholder="Deployment location(s)" maxLength={300} style={field}/>
      <textarea name="requirements" placeholder="Unique requirements, shift hours, certifications or other notes (optional)" maxLength={1000} rows={5} style={field}/>
      <label style={consentStyle}><input required type="checkbox" name="pdpaConsent"/> <span>I consent to QY Workforce using these details to respond to and manage this manpower enquiry, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <label style={consentStyle}><input type="checkbox" name="whatsappConsent"/> <span>I agree to be contacted on WhatsApp about this enquiry, including by an automated qualification assistant. I can ask to stop messages at any time.</span></label>
      <button disabled={state==='sending'} style={buttonStyle}>{state==='sending'?'Submitting…':'Request flexible workers'}</button>
      {state==='error' && <p role="alert">We could not submit this enquiry. Please check the required fields and try again.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
const consentStyle = {display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5};
const buttonStyle = {padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16};
