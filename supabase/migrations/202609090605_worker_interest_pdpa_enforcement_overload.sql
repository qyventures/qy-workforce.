create or replace function public.submit_worker_interest_public(
  p_full_name text,
  p_email text,
  p_phone text,
  p_work_interest text,
  p_availability text,
  p_preferred_locations text,
  p_pdpa_consent boolean,
  p_notes text default null,
  p_source text default 'website_worker',
  p_campaign text default 'meta_worker_gig_preview',
  p_whatsapp_consent boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lead_id uuid := gen_random_uuid();
  v_now timestamptz := now();
  v_email text := lower(trim(coalesce(p_email,'')));
  v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g');
begin
  if p_pdpa_consent is not true then raise exception 'PDPA consent required'; end if;
  if char_length(trim(coalesce(p_full_name,''))) not between 2 and 120 then raise exception 'invalid name'; end if;
  if char_length(v_email) > 254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid email'; end if;
  if v_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'invalid phone'; end if;
  if char_length(trim(coalesce(p_work_interest,''))) not between 2 and 200 then raise exception 'invalid work interest'; end if;
  if char_length(trim(coalesce(p_availability,''))) not between 2 and 500 then raise exception 'invalid availability'; end if;
  if char_length(trim(coalesce(p_preferred_locations,''))) not between 2 and 300 then raise exception 'invalid locations'; end if;
  if p_notes is not null and char_length(p_notes) > 1000 then raise exception 'invalid notes'; end if;
  if char_length(coalesce(p_source,'')) > 80 or char_length(coalesce(p_campaign,'')) > 120 then raise exception 'invalid tracking'; end if;

  insert into public.worker_interest_leads(
    id,full_name,email,phone,work_interest,availability,preferred_locations,notes,
    consent_at,whatsapp_consent_at,source,campaign,qualification_status
  ) values (
    v_lead_id,trim(p_full_name),v_email,v_phone,trim(p_work_interest),trim(p_availability),trim(p_preferred_locations),nullif(trim(coalesce(p_notes,'')),''),
    v_now,case when p_whatsapp_consent then v_now else null end,
    coalesce(nullif(trim(p_source),''),'website_worker'),
    coalesce(nullif(trim(p_campaign),''),'meta_worker_gig_preview'),
    case when p_whatsapp_consent then 'queued' else 'new' end
  );

  if p_whatsapp_consent then
    insert into public.lead_qualification_queue(lead_type,lead_id,channel,sender,status)
    values('worker',v_lead_id,'whatsapp','+6580227816','queued')
    on conflict (lead_type,lead_id,channel) do nothing;
  end if;

  return jsonb_build_object('lead_id',v_lead_id,'qualification_queued',p_whatsapp_consent);
end $$;

revoke all on function public.submit_worker_interest_public(text,text,text,text,text,text,boolean,text,text,text,boolean) from public;
grant execute on function public.submit_worker_interest_public(text,text,text,text,text,text,boolean,text,text,text,boolean) to anon, authenticated, service_role;
comment on function public.submit_worker_interest_public(text,text,text,text,text,text,boolean,text,text,text,boolean) is
  'Public worker-interest intake with mandatory explicit PDPA consent and opt-in-only WhatsApp qualification queueing.';
