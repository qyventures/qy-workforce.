-- Public employer lead intake without exposing tables or requiring a service-role key in the web runtime.
-- The RPC validates/bounds all fields, records consent, queues WhatsApp only after explicit opt-in,
-- and returns a short-lived per-lead sync token used only to report Google Sheet delivery status.

alter table public.employer_leads
  add column if not exists sheet_sync_token_hash text;

create or replace function public.submit_employer_lead_public(
  p_company_name text,
  p_contact_name text,
  p_email text,
  p_phone text,
  p_manpower_request text,
  p_pdpa_consent boolean,
  p_source text default 'website_employer',
  p_campaign text default 'qy_workforce_employer_leads',
  p_whatsapp_consent boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lead_id uuid := gen_random_uuid();
  v_now timestamptz := now();
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_email text := lower(trim(coalesce(p_email,'')));
  v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
  v_request text := trim(coalesce(p_manpower_request,''));
begin
  if p_pdpa_consent is not true then raise exception 'PDPA consent required'; end if;
  if char_length(trim(coalesce(p_company_name,''))) not between 2 and 160 then raise exception 'invalid company'; end if;
  if char_length(trim(coalesce(p_contact_name,''))) not between 2 and 120 then raise exception 'invalid contact'; end if;
  if char_length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid email'; end if;
  if v_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'invalid phone'; end if;
  if char_length(v_request) not between 2 and 1000 then raise exception 'invalid manpower request'; end if;
  if char_length(coalesce(p_source,'')) > 80 or char_length(coalesce(p_campaign,'')) > 120 then raise exception 'invalid tracking'; end if;

  insert into public.employer_leads(
    id, company_name, contact_name, email, phone,
    deployment_timeline, roles_headcount, location, requirements, manpower_need,
    consent_at, whatsapp_consent_at, source, campaign, qualification_status,
    sheet_sync_status, sheet_sync_token_hash
  ) values (
    v_lead_id, trim(p_company_name), trim(p_contact_name), v_email, v_phone,
    'To be confirmed', v_request, 'To be confirmed', v_request, v_request,
    v_now, case when p_whatsapp_consent then v_now else null end,
    coalesce(nullif(trim(p_source),''),'website_employer'),
    coalesce(nullif(trim(p_campaign),''),'qy_workforce_employer_leads'),
    case when p_whatsapp_consent then 'queued' else 'new' end,
    'pending', encode(digest(v_token, 'sha256'),'hex')
  );

  if p_whatsapp_consent then
    insert into public.lead_qualification_queue(lead_type, lead_id, channel, sender, status)
    values ('employer', v_lead_id, 'whatsapp', '+6580227816', 'queued')
    on conflict (lead_type, lead_id, channel) do nothing;
  end if;

  return jsonb_build_object('lead_id', v_lead_id, 'sheet_sync_token', v_token, 'qualification_queued', p_whatsapp_consent);
end $$;

revoke all on function public.submit_employer_lead_public(text,text,text,text,text,boolean,text,text,boolean) from public;
grant execute on function public.submit_employer_lead_public(text,text,text,text,text,boolean,text,text,boolean) to anon;

create or replace function public.mark_employer_lead_sheet_sync_public(
  p_lead_id uuid,
  p_sync_token text,
  p_status text,
  p_error text default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
begin
  if p_status not in ('synced','pending_retry','failed') then raise exception 'invalid status'; end if;
  if p_error is not null and char_length(p_error) > 500 then raise exception 'error too long'; end if;
  select sheet_sync_token_hash into v_hash from public.employer_leads where id=p_lead_id for update;
  if v_hash is null or v_hash <> encode(digest(coalesce(p_sync_token,''), 'sha256'),'hex') then return false; end if;
  update public.employer_leads
     set sheet_sync_status=p_status,
         sheet_synced_at=case when p_status='synced' then now() else sheet_synced_at end,
         sheet_sync_error=case when p_status='synced' then null else p_error end,
         sheet_sync_token_hash=case when p_status='synced' then null else sheet_sync_token_hash end
   where id=p_lead_id;
  return true;
end $$;

revoke all on function public.mark_employer_lead_sheet_sync_public(uuid,text,text,text) from public;
grant execute on function public.mark_employer_lead_sheet_sync_public(uuid,text,text,text) to anon;
