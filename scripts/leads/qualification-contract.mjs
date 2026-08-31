export const QY_WORKFORCE_WHATSAPP_SENDER = '+6580227816';
export const QY_WORKFORCE_WHATSAPP_DISPLAY_NAME = 'QY Workforce';

export const QUALIFICATION_RULES = Object.freeze({
  employer: {
    collect: ['roles_headcount', 'deployment_timeline', 'location', 'shift_schedule', 'budget_expectation', 'unique_requirements'],
    objective: 'Clarify an employer manpower enquiry for BD handoff.',
  },
  worker: {
    collect: ['work_interest', 'availability', 'preferred_locations', 'pay_expectation', 'experience_or_certifications', 'unique_requirements'],
    objective: 'Clarify a worker gig-interest enquiry for recruitment handoff.',
  },
});

export const SAFETY_RULES = [
  'Only message leads with an explicit whatsapp_consent_at timestamp.',
  'Do not promise pricing, guaranteed fulfilment, employment, eligibility, placement or deployment.',
  'Do not request NRIC, FIN, passport, Singpass credentials, bank credentials or other identity secrets in WhatsApp qualification.',
  'Stop automated follow-up if the lead asks to stop or withdraws consent.',
  'Escalate pricing, contract, legal, complaint and sensitive eligibility questions to a human.',
];

export function buildQualificationInstruction(leadType) {
  const config = QUALIFICATION_RULES[leadType];
  if (!config) throw new Error('Unsupported lead type');
  return [
    'You are the QY Workforce lead qualification assistant.',
    config.objective,
    `Collect only what is necessary: ${config.collect.join(', ')}.`,
    'Ask one or two concise questions at a time and avoid repeating facts already supplied.',
    'When enough information is available, return a structured summary and a 0-100 lead score.',
    'Use higher scores for clear role/availability, near-term timeline, location and actionable requirements; do not infer protected or sensitive traits.',
    ...SAFETY_RULES,
  ].join('\n');
}

export function buildBdHandoff({ lead, summary, score, status = 'handoff_ready', conversationId = null }) {
  return {
    createdAt: lead.created_at,
    leadType: lead.lead_type,
    source: lead.source,
    campaign: lead.campaign,
    name: lead.name,
    company: lead.company ?? '',
    contactNumber: lead.phone,
    email: lead.email,
    whatsappOptIn: Boolean(lead.whatsapp_consent_at),
    timeline: lead.timeline ?? '',
    roles: lead.roles ?? '',
    headcount: lead.headcount ?? '',
    location: lead.location ?? '',
    schedule: lead.schedule ?? '',
    budgetOrPay: lead.budget_or_pay ?? '',
    requirements: lead.requirements ?? '',
    aiQualificationSummary: summary,
    leadScore: score,
    status,
    bdOwner: lead.bd_owner ?? '',
    lastContacted: lead.last_contacted ?? '',
    nextAction: lead.next_action ?? 'BD review and follow-up',
    nextFollowUp: lead.follow_up_at ?? '',
    consentTimestamp: lead.whatsapp_consent_at ?? lead.consent_at,
    conversationId: conversationId ?? '',
    notes: lead.notes ?? '',
  };
}

export const GOOGLE_SHEET_COLUMNS = [
  'Created At','Lead Type','Source','Campaign','Name','Company','Contact Number','Email','WhatsApp Opt-in',
  'Deployment / Work Timeline','Roles Needed / Interested In','Headcount','Location','Shift / Schedule','Budget / Expected Pay',
  'Unique Requirements','AI Qualification Summary','Lead Score','Status','BD Owner','Last Contacted','Next Action','Next Follow-up',
  'Consent Timestamp','Conversation ID','Notes',
];
