-- Require authenticated application users to change attendance geofences only through an audited RPC.
-- Direct SQL maintenance remains possible when auth.uid() is null (e.g. migrations/admin maintenance).

create or replace function public.guard_site_geofence_update()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (new.latitude, new.longitude, new.geofence_radius_m)
       is distinct from
     (old.latitude, old.longitude, old.geofence_radius_m)
  then
    if auth.uid() is not null
       and coalesce(current_setting('app.geofence_change_authorized', true), '') <> old.id::text
    then
      raise exception 'site geofence changes must use update_site_geofence';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.guard_site_geofence_update() from public;

DROP TRIGGER IF EXISTS sites_geofence_change_guard ON public.sites;
create trigger sites_geofence_change_guard
before update of latitude, longitude, geofence_radius_m on public.sites
for each row execute function public.guard_site_geofence_update();

create or replace function public.update_site_geofence(
  p_site_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_radius_m integer,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_lat numeric;
  v_old_lon numeric;
  v_old_radius integer;
  v_reason text;
begin
  if auth.uid() is null or not public.is_ops() then
    raise exception 'not authorised';
  end if;

  if p_latitude is null or p_longitude is null then
    raise exception 'latitude and longitude are required';
  end if;
  if p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid coordinates';
  end if;
  if p_radius_m is null or p_radius_m < 25 or p_radius_m > 2000 then
    raise exception 'geofence radius must be between 25 and 2000 metres';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'change reason required';
  end if;
  if length(v_reason) > 500 then
    raise exception 'change reason too long';
  end if;

  select latitude, longitude, geofence_radius_m
    into v_old_lat, v_old_lon, v_old_radius
  from public.sites
  where id = p_site_id
  for update;

  if not found then
    raise exception 'site not found';
  end if;

  -- Authorise exactly this site for the duration of the guarded UPDATE only.
  perform set_config('app.geofence_change_authorized', p_site_id::text, true);

  update public.sites
  set latitude = p_latitude,
      longitude = p_longitude,
      geofence_radius_m = p_radius_m
  where id = p_site_id;

  perform set_config('app.geofence_change_authorized', '', true);

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'site.geofence_changed',
    'site',
    p_site_id,
    jsonb_build_object(
      'reason', v_reason,
      'location_changed', (v_old_lat, v_old_lon) is distinct from (p_latitude, p_longitude),
      'old_radius_m', v_old_radius,
      'new_radius_m', p_radius_m
    )
  );
end;
$$;

revoke all on function public.update_site_geofence(uuid,numeric,numeric,integer,text) from public;
grant execute on function public.update_site_geofence(uuid,numeric,numeric,integer,text) to authenticated;

comment on function public.update_site_geofence(uuid,numeric,numeric,integer,text) is
  'Ops/Admin-only audited mutation boundary for attendance geofence coordinates and radius.';
