begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('22000000-0000-4000-8000-%s', lpad(n::text,12,'0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text,12,'0'))::uuid,
       now()-interval '1 minute', now() from unnest(array[1,2,3]) n;
insert into auth.mfa_amr_claims (id,session_id,created_at,updated_at,authentication_method)
select gen_random_uuid(),id,now(),now(),'password' from auth.sessions
where id::text like '22000000-0000-4000-8000-%';
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims',json_build_object(
    'sub',format('00000000-0000-4000-8000-%s',lpad(n::text,12,'0')),
    'session_id',format('22000000-0000-4000-8000-%s',lpad(n::text,12,'0')),
    'role','authenticated')::text,true)
$$;
create function pg_temp.names(items jsonb) returns text[] language sql as $$
  select array_agg(e->>'name' order by n) from jsonb_array_elements(items) with ordinality a(e,n)
$$;
create temp table saved (key text primary key, value jsonb);
grant all on saved to authenticated;
grant execute on function pg_temp.as_user(int), pg_temp.names(jsonb) to authenticated;
set local role authenticated;
select pg_temp.as_user(1);
insert into saved values ('g10',api.create_catalog_entry('grade','Lớp 10')),
  ('g11',api.create_catalog_entry('grade','Lớp 11'));
select is(pg_temp.names(api.list_catalog_entries('grade')),
  array['Lớp 6','Lớp 7','Lớp 8','Lớp 9','Lớp 10','Lớp 11'],
  'grade catalogs sort by character length then lexical name');
select is((pg_temp.names(api.list_catalog_entries('subject')))[1:3],
  array['Toán','Ngữ văn','Tiếng Anh'],'subject catalogs sort by character length');
insert into saved values ('site-long',api.create_site('Z10','Fictional')),
  ('site-b',api.create_site('Z2','Fictional')),('site-a',api.create_site('Z1','Fictional'));
select is((api.list_sites()->0->>'name'),'Z1','sites use length and lexical ordering');
insert into saved values
  ('room-long',api.create_room((select (value->>'id')::uuid from saved where key='site-a'),'Z10')),
  ('room-short',api.create_room((select (value->>'id')::uuid from saved where key='site-b'),'Z2'));
select is((api.list_rooms()->0->>'name'),'Z2','room names sort before site grouping');

select pg_temp.as_user(2);
insert into saved values
 ('c10',api.create_class('List regression 10','10000000-0000-4000-8000-000000000001',
   (select (value->>'id')::uuid from saved where key='g10'),(now() at time zone 'Asia/Ho_Chi_Minh')::date-10,(now() at time zone 'Asia/Ho_Chi_Minh')::date+20,null,2026)),
 ('c7',api.create_class('List regression 7','10000000-0000-4000-8000-000000000003',
   '10000000-0000-4000-8000-000000000012',(now() at time zone 'Asia/Ho_Chi_Minh')::date+1,(now() at time zone 'Asia/Ho_Chi_Minh')::date+20,null,2027)),
 ('c6',api.create_class('List regression 6','10000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000011',(now() at time zone 'Asia/Ho_Chi_Minh')::date-10,(now() at time zone 'Asia/Ho_Chi_Minh')::date+20,null,2026)),
 ('c11',api.create_class('List regression 11','10000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000011',(now() at time zone 'Asia/Ho_Chi_Minh')::date-10,(now() at time zone 'Asia/Ho_Chi_Minh')::date-1));
select is(pg_temp.names(api.list_classes('List regression')->'items'),array['List regression 6','List regression 7','List regression 10','List regression 11'],
  'class list uses length-first sorting across all dates');
select is(api.list_classes('List regression',false,1,2)->'items'->0->>'name','List regression 10',
  'sorting happens before pagination');
insert into saved values ('assignment',api.create_class_assignment(
  (select (value->>'id')::uuid from saved where key='c6'),
  '00000000-0000-4000-8000-000000000003','assistant',(now() at time zone 'Asia/Ho_Chi_Minh')::date-1,(now() at time zone 'Asia/Ho_Chi_Minh')::date+10));
select api.create_class_assignment((select (value->>'id')::uuid from saved where key='c10'),
  '00000000-0000-4000-8000-000000000003','teacher',(now() at time zone 'Asia/Ho_Chi_Minh')::date+1,(now() at time zone 'Asia/Ho_Chi_Minh')::date+10);
select is(api.list_classes(p_search=>'List regression',p_grade_id=>'10000000-0000-4000-8000-000000000011',
  p_subject_id=>'10000000-0000-4000-8000-000000000001',p_status=>'running',
  p_staff_id=>'00000000-0000-4000-8000-000000000003',p_school_year=>'2026',p_limit=>1)->>'total',
  '1','combined filters count before pagination and only match effective assignments');
select is(api.list_classes(p_search=>'List regression',p_status=>'upcoming')->>'total','1','upcoming uses business dates');
select is(api.list_classes(p_search=>'List regression',p_status=>'ended')->>'total','1','ended uses business dates');
select is(api.list_classes(p_search=>'List regression',p_status=>'open')->>'total','4','open is administrative state');
select is(api.list_classes(p_search=>'List regression',p_status=>'closed')->>'total','0','closed is administrative state');
select throws_ok($$select api.list_classes(p_status=>'active')$$,'PT400','validation_failed','RPC validates status');
select is(api.list_classes(p_search=>'no matches',p_status=>'closed')->'filterOptions',
  api.list_classes()->'filterOptions','filter options ignore search, filters and pagination');
-- Archived catalog references remain filterable for existing classes.
select pg_temp.as_user(1);
select api.archive_catalog_entry((select (value->>'id')::uuid from saved where key='g10'),'History',1);
select ok(api.list_classes()->'filterOptions'->'grades' @>
  jsonb_build_array(jsonb_build_object('id',(select value->>'id' from saved where key='g10'))),
  'filter options retain archived references');
select pg_temp.as_user(3);
select is(api.list_classes()->>'total','1','User sees only currently assigned class');
select is(api.list_classes()->'filterOptions'->'grades',
  jsonb_build_array(jsonb_build_object('id','10000000-0000-4000-8000-000000000011','name','Lớp 6','archived',false)),
  'grade options do not expose classes outside scope');
select is(api.list_classes(p_grade_id=>(select (value->>'id')::uuid from saved where key='g10'))->>'total',
  '0','guessing a grade does not widen class scope');
select pg_temp.as_user(2);
select api.end_class_assignment((select (value->>'id')::uuid from saved where key='assignment'),'End scope',1);
select pg_temp.as_user(3);
select is(api.list_classes()->'filterOptions',
  '{"grades":[],"subjects":[],"staff":[]}'::jsonb,'ended assignment removes options immediately');
reset role;
delete from auth.sessions where id='22000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select api.list_classes(p_status=>'open')$$,'PT401','session_invalid','revoked sessions cannot filter');
reset role;
select * from finish();
rollback;
