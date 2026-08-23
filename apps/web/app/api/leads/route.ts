import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

type LeadType = 'employer' | 'worker';

const MAX_REQUEST_BYTES = 16 * 1024;

function text(value: unknown, max: number) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  return v && v.length <= max ? v : null;
}

function validEmail(value: unknown) {
  const v = text(value, 254);
  return v && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v) ? v.toLowerCase() : null;
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store, max-age=0',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

export async function POST(request: NextRequest) {
  const contentType = request.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    return jsonResponse({ ok: false, message: 'Unsupported request format.' }, 415);
  }

  const contentLength = Number(request.headers.get('content-length') ?? '0');
  if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BYTES) {
    return jsonResponse({ ok: false, message: 'Request is too large.' }, 413);
  }

  // Browser form submissions are same-origin. Reject an explicitly foreign
  // Origin to reduce cross-site spam while still allowing trusted server-side
  // health checks and tests that do not send an Origin header.
  const origin = request.headers.get('origin');
  if (origin) {
    let requestOrigin: string;
    try {
      requestOrigin = new URL(origin).origin;
    } catch {
      return jsonResponse({ ok: false }, 403);
    }
    if (requestOrigin !== request.nextUrl.origin) {
      return jsonResponse({ ok: false }, 403);
    }
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) {
    return jsonResponse({ ok: false, message: 'Enquiries are temporarily unavailable.' }, 503);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ ok: false }, 400);
  }

  // Honeypot field. Do not reveal to bots why the request was discarded.
  if (text(body.website, 200)) return jsonResponse({ ok: true });

  const type = body.type as LeadType;
  const consent = body.consent === true;
  const email = validEmail(body.email);
  if (!consent || !email || (type !== 'employer' && type !== 'worker')) {
    return jsonResponse({ ok: false, message: 'Please complete the required fields.' }, 400);
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (type === 'employer') {
    const companyName = text(body.companyName, 160);
    const contactName = text(body.contactName, 120);
    if (!companyName || !contactName) return jsonResponse({ ok: false }, 400);
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
    if (error) return jsonResponse({ ok: false, message: 'Unable to submit right now.' }, 500);
  } else {
    const fullName = text(body.fullName, 120);
    if (!fullName) return jsonResponse({ ok: false }, 400);
    const { error } = await supabase.from('worker_interest_leads').insert({
      full_name: fullName,
      email,
      phone: text(body.phone, 32),
      work_interest: text(body.workInterest, 200),
      consent_at: new Date().toISOString(),
      source: 'website',
    });
    if (error) return jsonResponse({ ok: false, message: 'Unable to submit right now.' }, 500);
  }

  return jsonResponse({ ok: true });
}
