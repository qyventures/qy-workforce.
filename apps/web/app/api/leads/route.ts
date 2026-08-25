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

function validPhone(value: unknown) {
  const v = text(value, 32);
  if (!v) return null;
  const compact = v.replace(/[\s().-]/g, '');
  return /^\+?[0-9]{8,15}$/.test(compact) ? compact : null;
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

  if (text(body.website, 200)) return jsonResponse({ ok: true });

  const type = body.type as LeadType;
  const pdpaConsent = body.pdpaConsent === true;
  const whatsappConsent = body.whatsappConsent === true;
  const email = validEmail(body.email);
  const phone = validPhone(body.phone);
  if (!pdpaConsent || !email || !phone || (type !== 'employer' && type !== 'worker')) {
    return jsonResponse({ ok: false, message: 'Please complete the required fields.' }, 400);
  }

  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const now = new Date().toISOString();
  let leadId: string | null = null;

  if (type === 'employer') {
    const companyName = text(body.companyName, 160);
    const contactName = text(body.contactName, 120);
    const deploymentTimeline = text(body.deploymentTimeline, 160);
    const rolesHeadcount = text(body.rolesHeadcount, 500);
    const location = text(body.location, 300);
    if (!companyName || !contactName || !deploymentTimeline || !rolesHeadcount || !location) {
      return jsonResponse({ ok: false, message: 'Please complete the required fields.' }, 400);
    }

    const { data, error } = await supabase.from('employer_leads').insert({
      company_name: companyName,
      contact_name: contactName,
      email,
      phone,
      deployment_timeline: deploymentTimeline,
      roles_headcount: rolesHeadcount,
      location,
      requirements: text(body.requirements, 1000),
      consent_at: now,
      whatsapp_consent_at: whatsappConsent ? now : null,
      source: 'website_employer',
      campaign: 'meta_employer_flexible_worker_preview',
      qualification_status: whatsappConsent ? 'queued' : 'new',
    }).select('id').single();
    if (error || !data?.id) return jsonResponse({ ok: false, message: 'Unable to submit right now.' }, 500);
    leadId = data.id;
  } else {
    const fullName = text(body.fullName, 120);
    const workInterest = text(body.workInterest, 200);
    const availability = text(body.availability, 500);
    const preferredLocations = text(body.preferredLocations, 300);
    if (!fullName || !workInterest || !availability || !preferredLocations) {
      return jsonResponse({ ok: false, message: 'Please complete the required fields.' }, 400);
    }

    const { data, error } = await supabase.from('worker_interest_leads').insert({
      full_name: fullName,
      email,
      phone,
      work_interest: workInterest,
      availability,
      preferred_locations: preferredLocations,
      notes: text(body.notes, 1000),
      consent_at: now,
      whatsapp_consent_at: whatsappConsent ? now : null,
      source: 'website_worker',
      campaign: 'meta_worker_gig_preview',
      qualification_status: whatsappConsent ? 'queued' : 'new',
    }).select('id').single();
    if (error || !data?.id) return jsonResponse({ ok: false, message: 'Unable to submit right now.' }, 500);
    leadId = data.id;
  }

  if (whatsappConsent && leadId) {
    const { error: queueError } = await supabase.from('lead_qualification_queue').insert({
      lead_type: type,
      lead_id: leadId,
      channel: 'whatsapp',
      sender: '+6584317050',
      status: 'queued',
    });
    if (queueError) {
      // Preserve the lead and consent even if qualification dispatch is temporarily unavailable.
      return jsonResponse({ ok: true, qualificationQueued: false });
    }
  }

  return jsonResponse({ ok: true, qualificationQueued: whatsappConsent });
}
