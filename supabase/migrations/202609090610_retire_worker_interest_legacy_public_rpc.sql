revoke all on function public.submit_worker_interest_public(text,text,text,text,text,text,text,text,text,boolean) from public, anon, authenticated;
grant execute on function public.submit_worker_interest_public(text,text,text,text,text,text,text,text,text,boolean) to service_role;
comment on function public.submit_worker_interest_public(text,text,text,text,text,text,text,text,text,boolean) is
  'Legacy worker-interest intake retained for service-role compatibility only. Public callers must use the PDPA-consent overload.';
