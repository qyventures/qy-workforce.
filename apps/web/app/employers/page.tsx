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
    {state==='done' ? <div style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Enquiry received.</strong><p>Our team can review the requirement once the staging/live workflow is activated.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <input required name="companyName" placeholder="Company name" maxLength={160} style={field}/>
      <input required name="contactName" placeholder="Your name" maxLength={120} style={field}/>
      <input required type="email" name="email" placeholder="Work email" maxLength={254} style={field}/>
      <input name="phone" placeholder="Phone (optional)" maxLength={32} style={field}/>
      <select name="industry" style={field} defaultValue=""><option value="" disabled>Industry</option><option>Hospitality</option><option>F&B</option><option>Cleaning</option><option>Retail</option><option>Promotions</option><option>Events</option><option>Other</option></select>
      <textarea name="manpowerNeed" placeholder="What roles, headcount, dates or locations do you need?" maxLength={1000} rows={6} style={field}/>
      <label style={{display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5}}><input required type="checkbox" name="consent"/> <span>I consent to QY Workforce using these details to respond to my enquiry, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <button disabled={state==='sending'} style={{padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16}}>{state==='sending'?'Submitting…':'Request manpower'}</button>
      {state==='error' && <p role="alert">We could not submit this enquiry. Please try again later.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
