import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

type LeadType = 'employer' | 'worker';

function text(value: unknown, max: number) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  return v && v.length <= max ? v : null;
}

function validEmail(value: unknown) {
  const v = text(value, 254);
  return v && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v) ? v.toLowerCase() : null;
}

export async function POST(request: NextRequest) {
  const contentType = request.headers.get('content-type') || '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    return NextResponse.json({ ok: false }, { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    return NextResponse.json({ ok: false, message: 'Enquiries are temporarily unavailable.' }, { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }

  let body: Record<string, unknown>;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > 16 * 1024) throw new Error('request too large');
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('invalid body');
    body = parsed as Record<string, unknown>;
  } catch {
    return NextResponse.json({ ok: false }, { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  // Honeypot field. Do not reveal to bots why the request was discarded.
  if (text(body.website, 200)) return NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });

  const type = body.type as LeadType;
  const consent = body.consent === true;
  const email = validEmail(body.email);
  if (!consent || !email || (type !== 'employer' && type !== 'worker')) {
    return NextResponse.json({ ok: false, message: 'Please complete the required fields.' }, { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (type === 'employer') {
    const companyName = text(body.companyName, 160);
    const contactName = text(body.contactName, 120);
    if (!companyName || !contactName) return NextResponse.json({ ok: false }, { status: 400, headers: { 'Cache-Control': 'no-store' } });
    const { error } = await supabase.from('employer_leads').insert({
      company_name: companyName,
      contact_name: contactName,
      email,
      phone: text(body.phone, 32),
      industry: text(body.industry, 80),
      manpower_need: text(body.manpowerNeed, 1000),
      consent_at: new Date().toISOString(),
      source: 'website',
    });
    if (error) return NextResponse.json({ ok: false, message: 'Unable to submit right now.' }, { status: 500, headers: { 'Cache-Control': 'no-store' } });
  } else {
    const fullName = text(body.fullName, 120);
    if (!fullName) return NextResponse.json({ ok: false }, { status: 400, headers: { 'Cache-Control': 'no-store' } });
    const { error } = await supabase.from('worker_interest_leads').insert({
      full_name: fullName,
      email,
      phone: text(body.phone, 32),
      work_interest: text(body.workInterest, 200),
      consent_at: new Date().toISOString(),
      source: 'website',
    });
    if (error) return NextResponse.json({ ok: false, message: 'Unable to submit right now.' }, { status: 500, headers: { 'Cache-Control': 'no-store' } });
  }

  return NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
}
