-- Seed part 10: catalogs. Local/test only; fictional data.
-- Tòa A/Tòa B are the centre's current sites (SCHED-03) but stay data, never code.

insert into app.catalog_entries (id, kind, name, name_key, created_by)
select v.id, v.kind, v.name, app_private.name_key(v.name), '00000000-0000-4000-8000-000000000001'
from (values
  ('10000000-0000-4000-8000-000000000001'::uuid, 'subject', 'Toán'),
  ('10000000-0000-4000-8000-000000000002'::uuid, 'subject', 'Ngữ văn'),
  ('10000000-0000-4000-8000-000000000003'::uuid, 'subject', 'Tiếng Anh'),
  ('10000000-0000-4000-8000-000000000011'::uuid, 'grade', 'Lớp 6'),
  ('10000000-0000-4000-8000-000000000012'::uuid, 'grade', 'Lớp 7'),
  ('10000000-0000-4000-8000-000000000013'::uuid, 'grade', 'Lớp 8'),
  ('10000000-0000-4000-8000-000000000014'::uuid, 'grade', 'Lớp 9')
) as v (id, kind, name);

insert into app.sites (id, name, name_key, address, created_by)
select v.id, v.name, app_private.name_key(v.name), v.address, '00000000-0000-4000-8000-000000000001'
from (values
  ('11000000-0000-4000-8000-000000000001'::uuid, 'Tòa A', '1 Đường Thử nghiệm, Quận Mẫu'),
  ('11000000-0000-4000-8000-000000000002'::uuid, 'Tòa B', '2 Đường Thử nghiệm, Quận Mẫu')
) as v (id, name, address);

insert into app.rooms (id, site_id, name, name_key, created_by)
select v.id, v.site_id, v.name, app_private.name_key(v.name), '00000000-0000-4000-8000-000000000001'
from (values
  ('12000000-0000-4000-8000-000000000001'::uuid, '11000000-0000-4000-8000-000000000001'::uuid, 'P101'),
  ('12000000-0000-4000-8000-000000000002'::uuid, '11000000-0000-4000-8000-000000000001'::uuid, 'P102'),
  -- Same room name at another site is a different room (SCHED-02/03).
  ('12000000-0000-4000-8000-000000000003'::uuid, '11000000-0000-4000-8000-000000000002'::uuid, 'P101')
) as v (id, site_id, name);
