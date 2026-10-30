begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_table('app','attendance','attendance keyed by student and actual session');
select has_function('api','get_attendance',array['uuid'],'attendance reads historical eligibility');
select has_function('api','save_attendance',array['uuid','jsonb','text'],'attendance save is atomic');
insert into auth.sessions(id,user_id,created_at,updated_at)
select format('25000000-0000-4000-8000-%s',lpad(n::text,12,'0'))::uuid,
format('00000000-0000-4000-8000-%s',lpad(n::text,12,'0'))::uuid,now(),now() from generate_series(1,3) n;
insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method)
select gen_random_uuid(),id,now(),now(),'password' from auth.sessions where id::text like '25000000%';
create function pg_temp.actor(n int) returns void language sql as $$
select set_config('request.jwt.claims',jsonb_build_object('sub',format('00000000-0000-4000-8000-%s',lpad(n::text,12,'0')),
'session_id',format('25000000-0000-4000-8000-%s',lpad(n::text,12,'0')),'role','authenticated')::text,true) $$;
select pg_temp.actor(1);
create temp table fixture as select (api.create_class('Chuyên cần','10000000-0000-4000-8000-000000000001',
'10000000-0000-4000-8000-000000000011',app_private.business_date(now())-10,app_private.business_date(now())+20)->>'id')::uuid c,
app_private.business_date(now())-1 d;
select api.enroll_student(c,'13000000-0000-4000-8000-000000000001',d-2,d+1) from fixture;
select api.enroll_student(c,'13000000-0000-4000-8000-000000000002',d+1) from fixture;
select api.enroll_student(c,'13000000-0000-4000-8000-000000000003',d-3,d) from fixture;
insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,status)
select c,'makeup',d,'09:00',app_private.day_start(d)+interval '9 hours',app_private.day_start(d)+interval '10 hours','scheduled' from fixture;
create temp table snapshot as select api.get_attendance(id) data from app.class_sessions where class_id=(select c from fixture);
select is((select jsonb_array_length(data->'students') from snapshot),1,'historical roster includes only eligible students, even if now ended');
select is((select data#>>'{students,0,present}' from snapshot),null,'opening attendance does not mark present or absent');
create function pg_temp.save(present boolean,note text default null) returns jsonb language sql as $$
select api.save_attendance((data#>>'{session,id}')::uuid,jsonb_build_array(jsonb_build_object(
'studentId','13000000-0000-4000-8000-000000000001','present',present,'note',note)),data->>'fingerprint') from snapshot $$;
select is(pg_temp.save(false,'Cần trao đổi')#>>'{students,0,present}','false','saving explicitly records absence');
select throws_ok($$select pg_temp.save(true)$$,'PT409','version_conflict','a stale attendance roster cannot overwrite results');
update snapshot set data=api.get_attendance((data#>>'{session,id}')::uuid);
select is(pg_temp.save(true)#>>'{students,0,present}','true','editing absent to present is allowed');
update snapshot set data=api.get_attendance((data#>>'{session,id}')::uuid);
select throws_ok($$select pg_temp.save(null)$$,'PT400','validation_failed','saved attendance cannot return to null');
select throws_ok($$select pg_temp.save(false,repeat('x',1001))$$,'PT400','validation_failed','notes above 1000 characters rejected');
select throws_ok($$select api.save_attendance((data#>>'{session,id}')::uuid,
'[{"studentId":"13000000-0000-4000-8000-000000000002","present":false,"note":null}]',data->>'fingerprint') from snapshot$$,
'PT400','validation_failed','foreign or ineligible students rejected');
select throws_ok($$select api.save_attendance((data#>>'{session,id}')::uuid,'[]',data->>'fingerprint') from snapshot$$,
'PT400','validation_failed','partial roster cannot implicitly omit students');
select is((select count(*)::int from app.attendance where session_id=(select (data#>>'{session,id}')::uuid from snapshot)),1,'one result per student/session');
select is((select count(*)::int from app.business_entity_versions where entity_kind='attendance' and changed_at=now()),2,'independent immutable history survives audit retention');
select is((select count(*)::int from app.audit_events where action='attendance.save' and created_at=now()),2,'each save has one audit');
select lives_ok($$select api.create_class_assignment(c,'00000000-0000-4000-8000-000000000003','assistant',d-3,d+10,null) from fixture$$,'assistant assignment');
select pg_temp.actor(3);
select lives_ok($$select pg_temp.save(true,'Trợ giảng cập nhật')$$,'current assistant may edit old attendance');
select pg_temp.actor(1);
select api.end_class_assignment(id,'Thu hồi',1) from app.class_assignments where account_id='00000000-0000-4000-8000-000000000003' and class_id=(select c from fixture);
select pg_temp.actor(3);
select throws_ok($$select api.get_attendance((data#>>'{session,id}')::uuid) from snapshot$$,'PT404','not_found','revoked assignment blocks old token');
select pg_temp.actor(1);
update snapshot set data=api.get_attendance((data#>>'{session,id}')::uuid);
create function pg_temp.fail_audit() returns trigger language plpgsql as $$ begin raise exception 'audit_failure'; end $$;
create trigger test_attendance_audit before insert on app.audit_events for each row execute function pg_temp.fail_audit();
select throws_ok($$select pg_temp.save(false)$$,'P0001','audit_failure','failed audit rolls back every result');
drop trigger test_attendance_audit on app.audit_events;
select is((select present from app.attendance where session_id=(select (data#>>'{session,id}')::uuid from snapshot)),true,'previous attendance preserved after audit failure');
select is((select note from app.attendance where session_id=(select (data#>>'{session,id}')::uuid from snapshot)),'Trợ giảng cập nhật','previous note preserved after audit failure');
select ok(not has_table_privilege('anon','app.attendance','select'),'anonymous cannot read attendance');
select ok(not has_table_privilege('authenticated','app.attendance','insert'),'SDK cannot write attendance directly');
select api.soft_delete_class_student(r.id,'Thêm lại hồ sơ',r.row_version) from app.class_students r,fixture f
where r.class_id=f.c and r.student_id='13000000-0000-4000-8000-000000000001';
select api.enroll_student(c,'13000000-0000-4000-8000-000000000001',d-2) from fixture;
select is((select jsonb_array_length(api.get_attendance((data#>>'{session,id}')::uuid)->'students') from snapshot),1,
'deleting and re-adding the class record does not duplicate historical attendance');
select is((select count(*)::int from app.attendance where session_id=(select (data#>>'{session,id}')::uuid from snapshot)),1,
'academic identity stays student/session after a new financial class record');
select is((select api.get_attendance((data#>>'{session,id}')::uuid)#>>'{students,0,present}' from snapshot),'true','old result survives re-add');
select * from finish();
rollback;


