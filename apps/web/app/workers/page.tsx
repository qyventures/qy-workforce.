'use client';

import { FormEvent, useState } from 'react';

export default function WorkersPage() {
  const [state, setState] = useState<'idle'|'sending'|'done'|'error'>('idle');
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setState('sending');
    const form = new FormData(e.currentTarget);
    const payload = {
      type: 'worker',
      fullName: form.get('fullName'),
      email: form.get('email'),
      phone: form.get('phone'),
      workInterest: form.get('workInterest'),
      website: form.get('website'),
      consent: form.get('consent') === 'on',
    };
    try {
      const res = await fetch('/api/leads', { method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify(payload) });
      setState(res.ok ? 'done' : 'error');
    } catch { setState('error'); }
  }
  return <main style={{maxWidth:820,margin:'0 auto',padding:'72px 24px',fontFamily:'Arial,sans-serif'}}>
    <p style={{letterSpacing:3,fontSize:12}}>QY WORKFORCE FOR WORKERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,68px)',marginBottom:16}}>Register your interest for flexible shifts.</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#444'}}>Tell us what kind of work you are interested in. This is an interest form only; identity verification and onboarding will happen separately in the app.</p>
    {state==='done' ? <div style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Interest received.</strong><p>We will use your details only for QY Workforce recruitment and onboarding follow-up.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <input required name="fullName" placeholder="Full name" maxLength={120} style={field}/>
      <input required type="email" name="email" placeholder="Email" maxLength={254} style={field}/>
      <input name="phone" placeholder="Phone (optional)" maxLength={32} style={field}/>
      <select name="workInterest" style={field} defaultValue=""><option value="" disabled>Work interest</option><option>Hospitality</option><option>F&B</option><option>Cleaning</option><option>Retail</option><option>Promotions</option><option>Events</option><option>Multiple roles</option></select>
      <label style={{display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5}}><input required type="checkbox" name="consent"/> <span>I consent to QY Workforce using these details for recruitment and onboarding follow-up, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <button disabled={state==='sending'} style={{padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16}}>{state==='sending'?'Submitting…':'Register interest'}</button>
      {state==='error' && <p role="alert">We could not submit your interest. Please try again later.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
