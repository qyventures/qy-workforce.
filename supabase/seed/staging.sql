-- Synthetic staging fixtures only. No auth users, identity data, credentials,
-- customer data, or production identifiers belong in this file.

insert into public.roles (id, code, name, description, active)
values
  ('00000000-0000-4000-8000-000000000001', 'staging_cleaner', 'Staging Cleaner', 'Synthetic preview role', true),
  ('00000000-0000-4000-8000-000000000002', 'staging_banquet', 'Staging Banquet Crew', 'Synthetic preview role', true)
on conflict (id) do update
set name = excluded.name, description = excluded.description, active = excluded.active;

insert into public.clients (id, name, active)
values ('00000000-0000-4000-8000-000000000010', 'Synthetic Staging Client', true)
on conflict (id) do update
set name = excluded.name, active = excluded.active;

insert into public.sites (id, client_id, name, address, latitude, longitude, geofence_radius_m, active)
values ('00000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000010', 'Synthetic Staging Site', '1 Synthetic Way, Singapore', 1.3521, 103.8198, 150, true)
on conflict (id) do update
set client_id = excluded.client_id, name = excluded.name, address = excluded.address,
    latitude = excluded.latitude, longitude = excluded.longitude,
    geofence_radius_m = excluded.geofence_radius_m, active = excluded.active;

insert into public.shifts (id, site_id, role_id, starts_at, ends_at, headcount, worker_rate, client_rate, status)
values ('00000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000001', date_trunc('day', now()) + interval '1 day 9 hours', date_trunc('day', now()) + interval '1 day 17 hours', 2, 14.00, 22.00, 'open')
on conflict (id) do update
set site_id = excluded.site_id, role_id = excluded.role_id, starts_at = excluded.starts_at,
    ends_at = excluded.ends_at, headcount = excluded.headcount,
    worker_rate = excluded.worker_rate, client_rate = excluded.client_rate, status = excluded.status;
