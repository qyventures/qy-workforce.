'use client';

import { FormEvent, useState } from 'react';

export default function WorkersPage() {
  const [state, setState] = useState<'idle'|'sending'|'done'|'error'>('idle');

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setState('sending');
    const form = new FormData(e.currentTarget);
    const params = new URLSearchParams(window.location.search);
    const source = params.get('utm_source') || 'website_worker';
    const campaign = params.get('utm_campaign') || 'qy_workforce_worker_leads';
    const eligibility = String(form.get('eligibility') || '').trim();
    const startReadiness = String(form.get('startReadiness') || '').trim();
    const notesRaw = String(form.get('notes') || '').trim();
    const notes = [
      `Work eligibility: ${eligibility}`,
      `Start readiness: ${startReadiness}`,
      notesRaw ? `Experience / notes: ${notesRaw}` : '',
      params.get('utm_content') ? `UTM content: ${params.get('utm_content')}` : '',
      params.get('utm_term') ? `UTM term: ${params.get('utm_term')}` : '',
    ].filter(Boolean).join('\n');

    const payload = {
      type: 'worker',
      fullName: form.get('fullName'),
      email: form.get('email'),
      phone: form.get('phone'),
      workInterest: form.get('workInterest'),
      availability: form.get('availability'),
      preferredLocations: form.get('preferredLocations'),
      notes,
      source,
      campaign,
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
    <p style={{letterSpacing:3,fontSize:12}}>QY WORKFORCE FOR WORKERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,68px)',marginBottom:16}}>Flexible shifts that fit your schedule.</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#444'}}>Register your interest for part-time and gig work across banquet, service crew, housekeeping, promotions/events, retail and logistics. Onboarding and eligibility checks happen separately.</p>
    {state==='done' ? <div style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Interest received.</strong><p>Our team will review your details and contact suitable candidates about onboarding and available shifts.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />
      <input required name="fullName" placeholder="Full name" maxLength={120} style={field}/>
      <input required type="tel" name="phone" placeholder="Contact number" maxLength={32} style={field}/>
      <input required type="email" name="email" placeholder="Email" maxLength={254} style={field}/>
      <select required name="eligibility" style={field} defaultValue="">
        <option value="" disabled>Work eligibility in Singapore</option>
        <option>Singapore Citizen</option>
        <option>Singapore PR</option>
        <option>Other valid work authorisation</option>
        <option>Not sure</option>
      </select>
      <select required name="workInterest" style={field} defaultValue="">
        <option value="" disabled>Preferred work type</option>
        <option>Banquet staff</option>
        <option>Service crew / F&B</option>
        <option>Housekeeping / cleaning</option>
        <option>Promoters / event crew</option>
        <option>Warehouse / logistics</option>
        <option>Retail staff</option>
        <option>Multiple roles</option>
      </select>
      <select required name="startReadiness" style={field} defaultValue="">
        <option value="" disabled>When can you start?</option>
        <option>Immediately / ASAP</option>
        <option>Within 1 week</option>
        <option>Within 2 weeks</option>
        <option>Later / specific dates only</option>
      </select>
      <textarea required name="availability" placeholder="Your availability e.g. weekdays evenings / weekends / specific dates" maxLength={500} rows={3} style={field}/>
      <input required name="preferredLocations" placeholder="Preferred work locations" maxLength={300} style={field}/>
      <textarea name="notes" placeholder="Experience, certifications or other notes (optional)" maxLength={1000} rows={5} style={field}/>
      <label style={consentStyle}><input required type="checkbox" name="pdpaConsent"/> <span>I consent to QY Workforce using these details for recruitment and onboarding follow-up, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
      <label style={consentStyle}><input type="checkbox" name="whatsappConsent"/> <span>I agree to be contacted on WhatsApp about QY Workforce opportunities, including by an automated qualification assistant. I can ask to stop messages at any time.</span></label>
      <button disabled={state==='sending'} style={buttonStyle}>{state==='sending'?'Submitting…':'Register for work'}</button>
      {state==='error' && <p role="alert">We could not submit your interest. Please check the required fields and try again.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
const consentStyle = {display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5};
const buttonStyle = {padding:'16px 20px',border:0,borderRadius:10,background:'#111',color:'#fff',fontWeight:700,fontSize:16};
