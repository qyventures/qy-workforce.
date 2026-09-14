'use client';

import { FormEvent, useState } from 'react';

export default function EmployersPage() {
  const [state, setState] = useState<'idle'|'sending'|'done'|'error'>('idle');
  const [isHiring, setIsHiring] = useState('');

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (isHiring !== 'yes') {
      window.location.href = '/workers';
      return;
    }

    setState('sending');
    const form = new FormData(e.currentTarget);
    const staffingType = String(form.get('staffingType') || '').trim();
    const workersNeeded = String(form.get('workersNeeded') || '').trim();
    const startDate = String(form.get('startDate') || '').trim();
    const location = String(form.get('location') || '').trim();
    const jobTitle = String(form.get('jobTitle') || '').trim();
    const notes = String(form.get('notes') || '').trim();
    const params = new URLSearchParams(window.location.search);
    const source = params.get('utm_source') || 'website_employer';
    const campaign = params.get('utm_campaign') || 'qy_workforce_employer_leads';
    const rolesHeadcount = `${staffingType} | ${workersNeeded} worker(s)`;
    const requirements = [
      jobTitle ? `Job title: ${jobTitle}` : '',
      `Staff needed: ${staffingType}`,
      `Headcount: ${workersNeeded}`,
      `Start date: ${startDate}`,
      `Location: ${location}`,
      notes ? `Additional details: ${notes}` : '',
      params.get('utm_content') ? `UTM content: ${params.get('utm_content')}` : '',
      params.get('utm_term') ? `UTM term: ${params.get('utm_term')}` : '',
    ].filter(Boolean).join('\n');

    const payload = {
      type: 'employer',
      companyName: form.get('companyName'),
      contactName: form.get('contactName'),
      email: form.get('email'),
      phone: form.get('phone'),
      deploymentTimeline: startDate,
      rolesHeadcount,
      location,
      requirements,
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

  return <main style={{maxWidth:760,margin:'0 auto',padding:'64px 24px',fontFamily:'Arial,sans-serif'}}>
    <p style={{letterSpacing:3,fontSize:12,fontWeight:700}}>QY WORKFORCE FOR EMPLOYERS</p>
    <h1 style={{fontSize:'clamp(40px,7vw,64px)',margin:'12px 0 16px'}}>Need part-time staff?</h1>
    <p style={{fontSize:18,lineHeight:1.6,color:'#444',maxWidth:650}}>Tell us your staffing needs and our team will contact you to understand the requirement and recommend suitable manpower support.</p>
    {state==='done' ? <div style={{padding:24,border:'1px solid #ddd',borderRadius:14,marginTop:32}}><strong>Thank you.</strong><p>Our team will contact you shortly to understand your manpower requirements.</p></div> :
    <form onSubmit={submit} style={{display:'grid',gap:16,marginTop:32}}>
      <input name="website" tabIndex={-1} autoComplete="off" style={{display:'none'}} aria-hidden="true" />

      <label style={{fontWeight:700}}>Are you looking to hire part-time staff for your business?</label>
      <select required name="isHiring" value={isHiring} onChange={(e)=>setIsHiring(e.target.value)} style={field}>
        <option value="" disabled>Please select</option>
        <option value="yes">Yes, I am hiring for a business</option>
        <option value="no">No, I am looking for work</option>
      </select>

      {isHiring === 'no' && <div style={noticeStyle}>This form is for employers. Submit to continue to our worker registration page.</div>}

      {isHiring === 'yes' && <>
        <input required name="companyName" placeholder="Company name" maxLength={160} style={field}/>
        <input required name="jobTitle" placeholder="Your job title" maxLength={120} style={field}/>
        <input required name="contactName" placeholder="Contact name" maxLength={120} style={field}/>
        <input required type="tel" name="phone" placeholder="Contact number" maxLength={32} style={field}/>
        <input required type="email" name="email" placeholder="Work email" maxLength={254} style={field}/>
        <select required name="staffingType" style={field} defaultValue="">
          <option value="" disabled>What type of staff do you need?</option>
          <option>Banquet staff</option>
          <option>Service crew / F&B</option>
          <option>Housekeeping / cleaning</option>
          <option>Promoters / event crew</option>
          <option>Warehouse / logistics</option>
          <option>Retail staff</option>
          <option>Other</option>
        </select>
        <input required type="number" min="1" max="999" name="workersNeeded" placeholder="How many workers do you need?" style={field}/>
        <input required type="date" name="startDate" aria-label="Required start date" style={field}/>
        <input required name="location" placeholder="Work location" maxLength={300} style={field}/>
        <textarea name="notes" placeholder="Shift hours, role details or other requirements (optional)" maxLength={1000} rows={5} style={field}/>
        <label style={consentStyle}><input required type="checkbox" name="pdpaConsent"/> <span>I consent to QY Workforce using these details to respond to and manage this manpower enquiry, in line with the <a href="/privacy">Privacy Notice</a>.</span></label>
        <label style={consentStyle}><input type="checkbox" name="whatsappConsent"/> <span>I agree to be contacted on WhatsApp about this enquiry, including by an automated qualification assistant. I can ask to stop messages at any time.</span></label>
      </>}

      <button disabled={state==='sending' || !isHiring} style={buttonStyle}>{state==='sending'?'Submitting…':isHiring==='no'?'Continue to worker registration':'Request Staffing Support'}</button>
      {state==='error' && <p role="alert">We could not submit this enquiry. Please check the required fields and try again.</p>}
    </form>}
  </main>;
}

const field = {padding:'14px 15px',border:'1px solid #bbb',borderRadius:10,fontSize:16,width:'100%',boxSizing:'border-box' as const};
const consentStyle = {display:'flex',gap:10,alignItems:'flex-start',lineHeight:1.5};
const buttonStyle = {padding:'16px 20px',border:0,borderRadius:10,background:'#0b1f33',color:'#fff',fontWeight:700,fontSize:16};
const noticeStyle = {padding:'12px 14px',border:'1px solid #ddd',borderRadius:10,background:'#f7f7f7',lineHeight:1.5};
