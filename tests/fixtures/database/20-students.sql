-- Seed part 20: students. Local/test only; fictional people and numbers.
-- Two students share a name key and differ by parent phone (STU-04).

with input (id, full_name, parent_name, birth_date, school) as (
  values
    ('13000000-0000-4000-8000-000000000001'::uuid, 'Nguyễn Văn An', 'Nguyễn Văn Bình', date '2013-05-02', 'THCS Thử nghiệm'),
    ('13000000-0000-4000-8000-000000000002'::uuid, 'Trần Thị Bích', 'Trần Văn Cường', date '2012-09-14', null),
    ('13000000-0000-4000-8000-000000000003'::uuid, 'Nguyen Van An', 'Lê Thị Dung', null, null)
)
insert into app.students (id, full_name, name_key, parent_name, birth_date, school, created_by)
select i.id, i.full_name, app_private.name_key(i.full_name), i.parent_name, i.birth_date, i.school,
       '00000000-0000-4000-8000-000000000001'
from input i
order by i.id;

insert into app.student_contacts (student_id, kind, phone, position)
values
  ('13000000-0000-4000-8000-000000000001', 'parent', '0900000001', 1),
  ('13000000-0000-4000-8000-000000000001', 'student', '0900000101', 1),
  ('13000000-0000-4000-8000-000000000002', 'parent', '0900000002', 1),
  ('13000000-0000-4000-8000-000000000003', 'parent', '0900000003', 1);
