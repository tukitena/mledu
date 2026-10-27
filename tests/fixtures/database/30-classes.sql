-- Seed part 30: classes. Local/test only; fictional data. No assignment is
-- seeded: account tests change the fixture User's type and delete it.

insert into app.classes (id, name, name_key, subject_id, grade_id, start_date, end_date, created_by)
select v.id, v.name, app_private.name_key(v.name), v.subject_id, v.grade_id, v.start_date, v.end_date,
       '00000000-0000-4000-8000-000000000001'
from (values
  ('14000000-0000-4000-8000-000000000001'::uuid, 'Toán 6A',
   '10000000-0000-4000-8000-000000000001'::uuid, '10000000-0000-4000-8000-000000000011'::uuid,
   date '2026-09-01', date '2027-05-31'),
  ('14000000-0000-4000-8000-000000000002'::uuid, 'Tiếng Anh 7B',
   '10000000-0000-4000-8000-000000000003'::uuid, '10000000-0000-4000-8000-000000000012'::uuid,
   date '2026-09-01', date '2027-05-31')
) as v (id, name, subject_id, grade_id, start_date, end_date);
