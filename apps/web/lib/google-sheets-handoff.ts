import { createSign } from 'node:crypto';

const SPREADSHEET_ID = '1dNf2Iu_Sk6y7bJ8x3FcC2cyD9dRqIqm1aAsLhDa-CC8';
const SHEET_TAB = 'Leads';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/spreadsheets';

const COLUMNS = ['Created At','Lead Type','Source','Campaign','Name','Company','Contact Number','Email','WhatsApp Opt-in','Deployment / Work Timeline','Roles Needed / Interested In','Headcount','Location','Shift / Schedule','Budget / Expected Pay','Unique Requirements','AI Qualification Summary','Lead Score','Status','BD Owner','Last Contacted','Next Action','Next Follow-up','Consent Timestamp','Conversation ID','Notes'];

function b64(v:string){ return Buffer.from(v).toString('base64url'); }
function clean(v:unknown){ const s=String(v??''); return /^(?:[=@-]|\+(?!\d))/.test(s)?`'${s}`:s; }
function normPhone(v:unknown){ return String(v??'').replace(/\D/g,''); }
function normEmail(v:unknown){ return String(v??'').trim().toLowerCase(); }

function assertion(email:string,key:string){
  const now=Math.floor(Date.now()/1000); const h=b64(JSON.stringify({alg:'RS256',typ:'JWT'}));
  const p=b64(JSON.stringify({iss:email,scope:SCOPE,aud:TOKEN_URL,iat:now,exp:now+3600})); const u=`${h}.${p}`;
  const signer=createSign('RSA-SHA256'); signer.update(u); signer.end(); return `${u}.${signer.sign(key,'base64url')}`;
}

export type EmployerSheetLead = { created_at:string; source:string; campaign:string; contact_name:string; company_name:string; phone:string; email:string; whatsapp_consent_at:string|null; consent_at:string; deployment_timeline?:string|null; roles_headcount?:string|null; location?:string|null; requirements?:string|null; ai_summary?:string|null; lead_score?:number|null; qualification_status?:string|null; next_action?:string|null; follow_up_at?:string|null; conversation_id?:string|null; };

export function createEmployerLeadSheetClient(){
  const configuredEmail=process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;
  const configuredKey=process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replace(/\\n/g,'\n');
  if(!configuredEmail||!configuredKey) throw new Error('Google Sheets service-account credentials are not configured');
  const serviceAccountEmail:string=configuredEmail;
  const privateKey:string=configuredKey;
  async function token(){ const r=await fetch(TOKEN_URL,{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:assertion(serviceAccountEmail,privateKey)})}); if(!r.ok) throw new Error(`Google OAuth failed (${r.status})`); const j=await r.json(); if(!j.access_token) throw new Error('Google OAuth missing token'); return j.access_token as string; }
  async function authFetch(url:string,init:RequestInit={}){ const t=await token(); return fetch(url,{...init,headers:{...(init.headers||{}),authorization:`Bearer ${t}`}}); }
  async function upsert(lead:EmployerSheetLead){
    const row=[lead.created_at,'employer',lead.source,lead.campaign,lead.contact_name,lead.company_name,lead.phone,lead.email,lead.whatsapp_consent_at?'Yes':'No',lead.deployment_timeline??'',lead.roles_headcount??'',lead.roles_headcount??'',lead.location??'','','',lead.requirements??'',lead.ai_summary??'',lead.lead_score??'',lead.qualification_status??'new','','',lead.next_action??'BD review and follow-up',lead.follow_up_at??'',lead.whatsapp_consent_at??lead.consent_at,lead.conversation_id??'',lead.requirements??''].map(clean);
    if(row.length!==COLUMNS.length) throw new Error('Sheet contract mismatch');
    const range=encodeURIComponent(`${SHEET_TAB}!A:Z`); const rr=await authFetch(`https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${range}`); if(!rr.ok) throw new Error(`Google Sheets read failed (${rr.status})`); const rows=(await rr.json()).values??[];
    let existing:number|null=null; const p=normPhone(lead.phone),e=normEmail(lead.email); for(let i=1;i<rows.length;i++){ if((p&&normPhone(rows[i]?.[6])===p)||(e&&normEmail(rows[i]?.[7])===e)){existing=i+1;break;} }
    const headers={'content-type':'application/json'}; let wr:Response;
    if(existing){ const r=encodeURIComponent(`${SHEET_TAB}!A${existing}:Z${existing}`); wr=await authFetch(`https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${r}?valueInputOption=RAW`,{method:'PUT',headers,body:JSON.stringify({values:[row]})}); }
    else { wr=await authFetch(`https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${range}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS`,{method:'POST',headers,body:JSON.stringify({values:[row]})}); }
    if(!wr.ok) throw new Error(`Google Sheets write failed (${wr.status})`); return {action:existing?'updated':'appended',row:existing};
  }
  return {upsert};
}
