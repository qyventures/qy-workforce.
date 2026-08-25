import { createSign } from 'node:crypto';
import { buildBdHandoff, GOOGLE_SHEET_COLUMNS } from './qualification-contract.mjs';

export const QY_WORKFORCE_LEAD_SHEET_ID = '1dNf2Iu_Sk6y7bJ8x3FcC2cyD9dRqIqm1aAsLhDa-CC8';
export const QY_WORKFORCE_LEAD_SHEET_TAB = 'Leads';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_SHEETS_SCOPE = 'https://www.googleapis.com/auth/spreadsheets';

function base64Url(value) {
  return Buffer.from(value).toString('base64url');
}

function sanitizeCell(value) {
  if (value === null || value === undefined) return '';
  const text = String(value);
  // Preserve legitimate international phone values such as +6584317050 while
  // neutralising formula-like prefixes in free-text fields. Writes use RAW,
  // and this extra guard protects downstream exports/copies as well.
  return /^(?:[=@-]|\+(?!\d))/.test(text) ? `'${text}` : text;
}

export function normalizePhone(value) {
  return String(value ?? '').replace(/\D/g, '');
}

export function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

export function handoffToRow({ lead, summary, score, status, conversationId }) {
  const handoff = buildBdHandoff({ lead, summary, score, status, conversationId });
  return [
    handoff.createdAt,
    handoff.leadType,
    handoff.source,
    handoff.campaign,
    handoff.name,
    handoff.company,
    handoff.contactNumber,
    handoff.email,
    handoff.whatsappOptIn ? 'Yes' : 'No',
    handoff.timeline,
    handoff.roles,
    handoff.headcount,
    handoff.location,
    handoff.schedule,
    handoff.budgetOrPay,
    handoff.requirements,
    handoff.aiQualificationSummary,
    handoff.leadScore,
    handoff.status,
    handoff.bdOwner,
    handoff.lastContacted,
    handoff.nextAction,
    handoff.nextFollowUp,
    handoff.consentTimestamp,
    handoff.conversationId,
    handoff.notes,
  ].map(sanitizeCell);
}

export function findExistingLeadRow(rows, { phone, email }) {
  const normalizedPhone = normalizePhone(phone);
  const normalizedEmail = normalizeEmail(email);
  for (let index = 1; index < rows.length; index += 1) {
    const row = rows[index] ?? [];
    const rowPhone = normalizePhone(row[6]);
    const rowEmail = normalizeEmail(row[7]);
    if ((normalizedPhone && rowPhone === normalizedPhone) || (normalizedEmail && rowEmail === normalizedEmail)) {
      return index + 1;
    }
  }
  return null;
}

function makeAssertion({ serviceAccountEmail, privateKey }) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64Url(JSON.stringify({
    iss: serviceAccountEmail,
    scope: GOOGLE_SHEETS_SCOPE,
    aud: GOOGLE_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign(privateKey, 'base64url');
  return `${unsigned}.${signature}`;
}

async function getAccessToken({ serviceAccountEmail, privateKey, fetchImpl }) {
  const assertion = makeAssertion({ serviceAccountEmail, privateKey });
  const response = await fetchImpl(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Google OAuth failed (${response.status})`);
  const data = await response.json();
  if (!data.access_token) throw new Error('Google OAuth did not return an access token');
  return data.access_token;
}

export function createLeadSheetClient({
  spreadsheetId = QY_WORKFORCE_LEAD_SHEET_ID,
  sheetTab = QY_WORKFORCE_LEAD_SHEET_TAB,
  serviceAccountEmail = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL,
  privateKey = process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  fetchImpl = fetch,
} = {}) {
  if (!serviceAccountEmail || !privateKey) {
    throw new Error('Google Sheets service-account credentials are not configured');
  }

  async function authorizedFetch(url, options = {}) {
    const token = await getAccessToken({ serviceAccountEmail, privateKey, fetchImpl });
    return fetchImpl(url, {
      ...options,
      headers: {
        ...(options.headers ?? {}),
        authorization: `Bearer ${token}`,
      },
    });
  }

  async function readRows() {
    const range = encodeURIComponent(`${sheetTab}!A:Z`);
    const response = await authorizedFetch(`https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${range}`);
    if (!response.ok) throw new Error(`Google Sheets read failed (${response.status})`);
    const data = await response.json();
    return data.values ?? [];
  }

  async function upsertQualifiedLead({ lead, summary, score, status = 'handoff_ready', conversationId = null }) {
    if (!lead?.whatsapp_consent_at) throw new Error('Refusing handoff without recorded WhatsApp consent');
    const row = handoffToRow({ lead, summary, score, status, conversationId });
    if (row.length !== GOOGLE_SHEET_COLUMNS.length) throw new Error('Google Sheet row contract mismatch');

    const rows = await readRows();
    const existingRow = findExistingLeadRow(rows, { phone: lead.phone, email: lead.email });
    const headers = { 'content-type': 'application/json' };
    let response;

    if (existingRow) {
      const range = encodeURIComponent(`${sheetTab}!A${existingRow}:Z${existingRow}`);
      response = await authorizedFetch(
        `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${range}?valueInputOption=RAW`,
        { method: 'PUT', headers, body: JSON.stringify({ values: [row] }) },
      );
    } else {
      const range = encodeURIComponent(`${sheetTab}!A:Z`);
      response = await authorizedFetch(
        `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${range}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS`,
        { method: 'POST', headers, body: JSON.stringify({ values: [row] }) },
      );
    }

    if (!response.ok) throw new Error(`Google Sheets handoff failed (${response.status})`);
    return { ok: true, action: existingRow ? 'updated' : 'appended', row: existingRow };
  }

  return { readRows, upsertQualifiedLead };
}
