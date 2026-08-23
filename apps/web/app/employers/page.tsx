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
      industry: form.get('industry'),
      manpowerNeed: form.get('manpowerNeed'),
      website: form.get('website'),
      consent: form.get('consent') === 'on',
    };
    try {
      const res = await fetch('/api/leads', { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(payload) });
      setState(res.ok ? 'done' : 'error');
    } catch { setState('error'); }
  }
  return <main style={{maxWidth:820,margin:'0 auto',padding:'72px 24px',fontFamily:'Arial,sans-serif'}}>
    <p style={{letterSpacing:3,fontSize:12}}>QY WORKFORCE FOR EMPLOYERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,68px)',marginBottom:16}}>Tell us where you need manpower.</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#444'}}>Hospitality, F&B, cleaning, retail, promotions and events. We will use your details only to respond to this manpower enquiry.</p>
    {state==='done' ? <div role="status" aria-live="polite" style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Enquiry received.</strong><p>Our team can review the requirement once the staging/live workflow is activated.</p></div> :
    <form onSubmit={submit} aria-describedby="employer-form-note" style={{display:'grid',gap:16,marginTop:32}}>
      <p id="employer-form-note" style={{margin:0,color:'#666',fontSize:14}}>Fields marked required must be completed before submission.</p>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <label style={labelStyle}>Company name<input required name="companyName" autoComplete="organization" maxLength={160} style={field}/></label>
      <label style={labelStyle}>Your name<input required name="contactName" autoComplete="name" maxLength={120} style={field}/></label>
      <label style={labelStyle}>Work email<input required type="email" name="email" autoComplete="email" inputMode="email" maxLength={254} style={field}/></label>
      <label style={labelStyle}>Phone <span style={optional}>(optional)</span><input name="phone" autoComplete="tel" inputMode="tel" maxLength={32} style={field}/></label>
      <label style={labelStyle}>Industry<select name="industry" style={field} defaultValue=""><option value="" disabled>Select an industry</option><option>Hospitality</option><option>F&B</option><option>Cleaning</option><option>Retail</option><option>Promotions</option><option>Events</option><option>Other</option></select></label>
      <label style={labelStyle}>Manpower requirement <span style={optional}>(optional)</span><textarea name="manpowerNeed" placeholder="Roles, headcount, dates or locations" maxLength={1000} rows={6} style={field}/></label>
      <label style={{display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5}}><input required type="checkbox" name="consent"/> <span>I consent to QY Workforce using these details to respond to my enquiry, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <button disabled={state==='sending'} aria-busy={state==='sending'} style={{padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16}}>{state==='sending'?'Submitting…':'Request manpower'}</button>
      {state==='error' && <p role="alert" aria-live="assertive">We could not submit this enquiry. Please try again later.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
const labelStyle = {display:'grid',gap:7,fontWeight:700,color:'#222'};
const optional = {fontWeight:400,color:'#667085',fontSize:14};
