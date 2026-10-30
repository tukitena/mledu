-- CLASS-03: nullable year, scoped filtering, version/history/audit atomicity.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.sessions (id, user_id, created_at, updated_at)
select format('21000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0'))::uuid,
       now() - interval '1 minute', now() from unnest(array[1,2,3]) n;
insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
select gen_random_uuid(), s.id, now(), now(), 'password' from auth.sessions s
where s.id::text like '21000000-0000-4000-8000-%';
create function pg_temp.as_user(n int) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', format('00000000-0000-4000-8000-%s', lpad(n::text, 12, '0')),
    'session_id', format('21000000-0000-4000-8000-%s', lpad(n::text, 12, '0')),
    'role', 'authenticated')::text, true)
$$;
create temp table results (key text primary key, value jsonb);
grant all on results to authenticated;
grant execute on function pg_temp.as_user(int) to authenticated;

select has_column('app', 'classes', 'school_year_start', 'classes store an optional school year');
set local role authenticated;
select pg_temp.as_user(2);
insert into results values ('year', api.create_class('School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date - 10, current_date + 50, null, 2026));
insert into results values ('same-year', api.create_class('School year test B',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date - 10, current_date + 50, null, 2026));
insert into results values ('none', api.create_class('School year test C',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date - 10, current_date + 50));
insert into results values ('other', api.create_class('School year test D',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date - 10, current_date + 50, null, 2027));
select is((select value->>'schoolYearStart' from results where key='year'),'2026',
  'create returns school year independently of class dates');
select is((select value->'schoolYearStart' from results where key='none'),'null'::jsonb,
  'omitted year creates an unassigned class');
select throws_ok($$select api.create_class('Invalid year',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date,current_date+10,null,9999)$$,'PT400','validation_failed','reject out-of-range year');
select is(api.list_classes('School year test',false,1,0,'2026')->>'total','2',
  'filter counts before pagination');
select is(jsonb_array_length(api.list_classes('School year test',false,1,0,'2026')->'items'),1,
  'page size applies after filtering');
select isnt(api.list_classes('School year test',false,1,0,'2026')->'items'->0->>'id',
  api.list_classes('School year test',false,1,1,'2026')->'items'->0->>'id',
  'second filtered page has a distinct row');
select is(api.list_classes('School year test',false,20,0,'none')->>'total','1','none filters NULL only');
select is(api.list_classes('School year test',false,20,0,'all')->>'total','4','all includes NULL');
select ok(api.list_classes('School year test C',false,20,0,'none')->'schoolYears' @> '[2026,2027]'::jsonb,
  'options ignore search, year and pagination');
select throws_ok($$select api.list_classes(null,false,20,0,'02026')$$,
  'PT400','validation_failed','RPC rejects malformed filters');
select throws_ok($$select api.list_classes(null,false,20,0,'9999')$$,
  'PT400','validation_failed','RPC rejects out-of-range filter');

-- Assign the User to only one year, not all classes with the same year.
select api.create_class_assignment((select (value->>'id')::uuid from results where key='year'),
  '00000000-0000-4000-8000-000000000003','teacher',current_date-1,current_date+5);
select pg_temp.as_user(3);
select is(api.list_classes(null,false,20,0,'2026')->>'total','1','User only sees assigned class');
select is(api.list_classes(null,false,20,0,'2027')->>'total','0','year filter never broadens scope');
select is(api.list_classes(null,false,20,0,'all')->'schoolYears','[2026]'::jsonb,
  'year options do not disclose unassigned class years');
select throws_ok(format($$select api.update_class(%L,'School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date-10,current_date+50,null,1,2028)$$,
  (select value->>'id' from results where key='year')),'PT403','forbidden','User cannot change year');
select pg_temp.as_user(2);
insert into results values ('updated', api.update_class(
  (select (value->>'id')::uuid from results where key='year'),'School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date-10,current_date+50,null,1,2028));
select is((select value->>'schoolYearStart' from results where key='updated'),'2028','can change year');
select throws_ok(format($$select api.update_class(%L,'School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date-10,current_date+50,null,1,null)$$,
  (select value->>'id' from results where key='year')),'PT409','version_conflict','stale version refused');
insert into results values ('legacy-update', api.update_class(
  (select (value->>'id')::uuid from results where key='year'),'School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date-10,current_date+50,'Legacy edit',2));
select is((select value->>'schoolYearStart' from results where key='legacy-update'),'2028',
  'legacy update without year preserves existing year');
insert into results values ('cleared', api.update_class(
  (select (value->>'id')::uuid from results where key='year'),'School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date-10,current_date+50,'Legacy edit',3,null));
select is((select value->'schoolYearStart' from results where key='cleared'),'null'::jsonb,
  'explicit NULL clears year');
reset role;
select is((select sanitized_snapshot->>'school_year_start' from app.business_entity_versions
  where entity_id=(select (value->>'id')::uuid from results where key='year') and revision=2),
  '2028','business history retains previous assigned year');
select is((select count(*) from app.audit_events where action='class.update'
  and entity_refs->>'class_id'=(select value->>'id' from results where key='year')),3::bigint,
  'each successful change writes one audit');

create function app_private.test_year_fail_audit() returns trigger language plpgsql as $$
begin raise exception 'injected audit failure'; end $$;
create trigger zz_test_year_fail before insert on app.audit_events
for each row execute function app_private.test_year_fail_audit();
set local role authenticated;
select throws_ok(format($$select api.update_class(%L,'School year test A',
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
  current_date-10,current_date+50,'Legacy edit',4,2029)$$,
  (select value->>'id' from results where key='year')),'P0001','injected audit failure',
  'audit failure rejects year change');
reset role;
select is((select school_year_start from app.classes where id=
  (select (value->>'id')::uuid from results where key='year')),null::integer,'failed change rolls back year');
select is((select row_version from app.classes where id=
  (select (value->>'id')::uuid from results where key='year')),4::bigint,'failed change rolls back version');
select is((select count(*) from app.business_entity_versions where entity_id=
  (select (value->>'id')::uuid from results where key='year')),4::bigint,'failed change rolls back history');

delete from auth.sessions where id='21000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.as_user(3);
select throws_ok($$select api.list_classes(null,false,20,0,'2026')$$,
  'PT401','session_invalid','revoked session cannot filter classes');
reset role;
select * from finish();
rollback;
