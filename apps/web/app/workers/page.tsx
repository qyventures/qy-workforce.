'use client';

import { FormEvent, useState, type ReactNode } from 'react';
import { ConsentBanner, SiteFooter, SiteHeader, trackConversion } from '../components/site-shell';

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
      if (res.ok) { setState('done'); trackConversion('worker_lead_submitted'); }
      else setState('error');
    } catch { setState('error'); }
  }
  return <main style={{minHeight:'100vh'}}><SiteHeader /><section style={{maxWidth:820,margin:'0 auto',padding:'72px 24px'}}>
    <p style={{letterSpacing:3,fontSize:12}}>QY WORKFORCE FOR WORKERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,68px)',marginBottom:16}}>Register your interest for flexible shifts.</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#475467'}}>Tell us what kind of work interests you. This is an interest form only; identity verification and onboarding happen separately before a shift is confirmed.</p>
    <p style={{fontSize:14,lineHeight:1.5,color:'#667085'}}>Please do not submit identification, bank, health, or other sensitive personal information through this form.</p>
    {state==='done' ? <div role="status" style={{padding:24,border:'1px solid #98A2B3',borderRadius:14,marginTop:32}}><strong>Interest received.</strong><p style={{marginBottom:0}}>Thank you. We will use your details only for QY Workforce recruitment and onboarding follow-up.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <Field label="Full name" required><input required name="fullName" autoComplete="name" maxLength={120} style={field}/></Field>
      <Field label="Email" required><input required type="email" name="email" autoComplete="email" maxLength={254} style={field}/></Field>
      <Field label="Phone"><input name="phone" type="tel" autoComplete="tel" maxLength={32} style={field}/></Field>
      <Field label="Work interest"><select name="workInterest" style={field} defaultValue=""><option value="">Select a work interest (optional)</option><option>Hospitality</option><option>F&B</option><option>Cleaning</option><option>Retail</option><option>Promotions</option><option>Events</option><option>Multiple roles</option></select></Field>
      <label style={{display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5}}><input required type="checkbox" name="consent"/> <span>I consent to QY Workforce using these details for recruitment and onboarding follow-up, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <button disabled={state==='sending'} style={{padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16}}>{state==='sending'?'Submitting…':'Register interest'}</button>
      {state==='error' && <p role="alert">We could not submit your interest. Please try again later.</p>}
    </form>}
  </section><SiteFooter /><ConsentBanner /></main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
function Field({ label, required, children }: { label: string; required?: boolean; children: ReactNode }) { return <label style={{display:'grid',gap:7,fontWeight:650,color:'#344054'}}>{label}{required ? ' *' : ''}{children}</label>; }
