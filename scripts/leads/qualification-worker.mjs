import { buildQualificationInstruction, QY_WORKFORCE_WHATSAPP_SENDER } from './qualification-contract.mjs';

const LEAD_TABLE = Object.freeze({ employer: 'employer_leads', worker: 'worker_interest_leads' });
const MAX_MESSAGE_LENGTH = 1200;

export function normalizeLead(leadType, row) {
  if (!LEAD_TABLE[leadType]) throw new Error('Unsupported lead type');
  return {
    ...row,
    lead_type: leadType,
    timeline: leadType === 'employer' ? row.deployment_timeline ?? '' : row.availability ?? '',
    roles: leadType === 'employer' ? row.roles_headcount ?? '' : row.work_interest ?? '',
    headcount: leadType === 'employer' ? row.roles_headcount ?? '' : '',
    location: leadType === 'employer' ? row.location ?? '' : row.preferred_locations ?? '',
    requirements: leadType === 'employer' ? row.requirements ?? '' : row.notes ?? '',
  };
}

export function buildOpeningMessage(lead) {
  if (!lead?.whatsapp_consent_at) throw new Error('WhatsApp consent is required');
  const name = String(lead.name ?? '').trim();
  const greeting = name ? `Hi ${name},` : 'Hi,';
  if (lead.lead_type === 'employer') {
    return `${greeting} this is QY Workforce. Thanks for your manpower enquiry. To help our team understand your requirement, could you share the roles/headcount you need and your preferred deployment date?`;
  }
  if (lead.lead_type === 'worker') {
    return `${greeting} this is QY Workforce. Thanks for your interest in flexible gig work. What type of work are you interested in, and when are you usually available?`;
  }
  throw new Error('Unsupported lead type');
}

function clampMessage(value) {
  const text = String(value ?? '').trim();
  if (!text) throw new Error('Refusing to send an empty WhatsApp message');
  return text.slice(0, MAX_MESSAGE_LENGTH);
}

export function createQualificationWorker({ repository, messenger, qualifier, sheetClient, now = () => new Date().toISOString() }) {
  if (!repository || !messenger || !qualifier || !sheetClient) throw new Error('Worker dependencies are required');

  async function startQueueItem(item) {
    const lead = normalizeLead(item.lead_type, await repository.getLead(item.lead_type, item.lead_id));
    if (!lead.whatsapp_consent_at) {
      await repository.updateQueue(item.id, { status: 'cancelled', last_error: 'WhatsApp consent missing or withdrawn', updated_at: now() });
      return { status: 'cancelled' };
    }
    if (item.sender !== QY_WORKFORCE_WHATSAPP_SENDER) throw new Error('Unexpected WhatsApp sender');
    const message = buildOpeningMessage(lead);
    const sent = await messenger.send({ from: item.sender, to: lead.phone, text: clampMessage(message) });
    await repository.addMessage({ lead_type: item.lead_type, lead_id: item.lead_id, direction: 'outbound', provider_message_id: sent?.id ?? null, message_text: message });
    await repository.updateQueue(item.id, { status: 'waiting_for_reply', attempts: (item.attempts ?? 0) + 1, last_error: null, updated_at: now() });
    await repository.updateLead(item.lead_type, item.lead_id, { qualification_status: 'in_progress' });
    return { status: 'waiting_for_reply' };
  }

  async function handleInbound({ leadType, leadId, text, providerMessageId = null }) {
    const lead = normalizeLead(leadType, await repository.getLead(leadType, leadId));
    if (!lead.whatsapp_consent_at) return { status: 'stopped' };
    const inbound = clampMessage(text);
    if (/^(stop|unsubscribe|cancel|quit|end)\b/i.test(inbound)) {
      await repository.addMessage({ lead_type: leadType, lead_id: leadId, direction: 'inbound', provider_message_id: providerMessageId, message_text: inbound });
      await repository.withdrawWhatsappConsent(leadType, leadId);
      await repository.cancelQueueForLead(leadType, leadId, 'Consent withdrawn by lead');
      return { status: 'stopped' };
    }
    await repository.addMessage({ lead_type: leadType, lead_id: leadId, direction: 'inbound', provider_message_id: providerMessageId, message_text: inbound });
    const history = await repository.getConversation(leadType, leadId);
    const result = await qualifier.qualify({ instruction: buildQualificationInstruction(leadType), lead, history });
    if (result.complete) {
      const score = Math.max(0, Math.min(100, Number(result.score) || 0));
      const summary = clampMessage(result.summary);
      await repository.updateLead(leadType, leadId, { qualification_status: 'handoff_ready', ai_summary: summary, lead_score: score, next_action: 'BD review and follow-up' });
      const conversationId = `${leadType}:${leadId}`;
      await sheetClient.upsertQualifiedLead({ lead, summary, score, status: 'handoff_ready', conversationId });
      await repository.markQueueForLead(leadType, leadId, { status: 'handoff_ready', updated_at: now(), last_error: null });
      return { status: 'handoff_ready', score };
    }
    const reply = clampMessage(result.reply);
    const sent = await messenger.send({ from: QY_WORKFORCE_WHATSAPP_SENDER, to: lead.phone, text: reply });
    await repository.addMessage({ lead_type: leadType, lead_id: leadId, direction: 'outbound', provider_message_id: sent?.id ?? null, message_text: reply });
    await repository.markQueueForLead(leadType, leadId, { status: 'waiting_for_reply', updated_at: now(), last_error: null });
    return { status: 'waiting_for_reply' };
  }

  return { startQueueItem, handleInbound };
}
