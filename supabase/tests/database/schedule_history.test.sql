begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_table('app', 'weekly_schedules', 'weekly revisions are business data');
select has_table('app', 'class_sessions', 'actual sessions have persistent identity');
select has_function('api', 'preview_schedule_change', array['uuid','jsonb'], 'changes can be previewed');
select has_function('api', 'apply_schedule_change', array['uuid','jsonb','text'], 'confirmation revalidates atomically');
insert into auth.sessions(id,user_id,created_at,updated_at)
select format('24000000-0000-4000-8000-%s',lpad(n::text,12,'0'))::uuid,
format('00000000-0000-4000-8000-%s',lpad(n::text,12,'0'))::uuid,now(),now() from generate_series(1,3) n;
insert into auth.mfa_amr_claims(id,session_id,created_at,updated_at,authentication_method)
select gen_random_uuid(),id,now(),now(),'password' from auth.sessions where id::text like '24000000%';
create function pg_temp.actor(n int) returns void language sql as $$
select set_config('request.jwt.claims',jsonb_build_object('sub',format('00000000-0000-4000-8000-%s',lpad(n::text,12,'0')),
'session_id',format('24000000-0000-4000-8000-%s',lpad(n::text,12,'0')),'role','authenticated')::text,true) $$;
select pg_temp.actor(1);
create temp table fixture as select
  (api.create_class('Lịch A','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
   app_private.business_date(now())-10,app_private.business_date(now())+20)->>'id')::uuid a,
  (api.create_class('Lịch B','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
   app_private.business_date(now())-10,app_private.business_date(now())+20)->>'id')::uuid b,
  app_private.business_date(now())+1 d;
create function pg_temp.sessions() returns setof app.class_sessions language sql as $$ select x.* from app.class_sessions x,fixture f where x.class_id in (f.a,f.b) $$;
create function pg_temp.cmd(k uuid,c jsonb) returns jsonb language plpgsql as $$
declare p jsonb;
begin p:=api.preview_schedule_change(k,c); return api.apply_schedule_change(k,c,p->>'token'); end $$;
create temp table changes as select jsonb_build_object('op','makeup','date',d,'startTime','09:00','endTime','10:00',
'roomId','12000000-0000-4000-8000-000000000001') c from fixture;
create temp table preview as select api.preview_schedule_change(a,c) p from fixture,changes;
select is((select count(*)::int from pg_temp.sessions()),0,'preview persists no sessions');
select is((select count(*)::int from app.audit_events where action='schedule.makeup' and created_at=now()),0,'preview persists no audit');
select is((select count(*)::int from app.business_entity_versions where entity_kind='class_session' and changed_at=now()),0,'preview persists no history');
select lives_ok($$select api.apply_schedule_change(a,c,p->>'token') from fixture,changes,preview$$,'confirmation creates a makeup without a source');
select is((select count(*)::int from pg_temp.sessions()),1,'one actual session');
select is((select count(*)::int from app.audit_events where action='schedule.makeup' and created_at=now()),1,'one audit for confirmation');
select throws_ok($$select api.apply_schedule_change(a,c,p->>'token') from fixture,changes,preview$$,
'PT409','version_conflict','a stale preview cannot apply again');
select throws_ok($$select api.preview_schedule_change(b,c) from fixture,changes$$,
'PT409','room_conflict','same room overlapping between classes is blocked');
select lives_ok($$select pg_temp.cmd(b,c||'{"startTime":"10:00","endTime":"11:00"}') from fixture,changes$$,
'adjacent room reservations are valid');
select lives_ok($$select pg_temp.cmd(b,c||'{"roomId":"12000000-0000-4000-8000-000000000003"}') from fixture,changes$$,
'same room name at another site is independent');
select lives_ok($$select pg_temp.cmd(b,c||'{"roomId":null}') from fixture,changes$$,'a room is optional');
select throws_ok($$select api.preview_schedule_change(a,c||jsonb_build_object('date',d-2)) from fixture,changes$$,
'PT409','session_started','a past makeup cannot be created');
select throws_ok($$select api.archive_room('12000000-0000-4000-8000-000000000001','Cất',1)$$,
'PT409','room_in_use','rooms with future use cannot be archived');
select pg_temp.actor(2);
select throws_ok($$select api.preview_schedule_change(null,jsonb_build_object('op','holiday','date',d,'name','Lễ')) from fixture$$,
'PT403','forbidden','receptionist cannot manage holidays');
select pg_temp.actor(1);
select lives_ok($$select pg_temp.cmd(null,jsonb_build_object('op','holiday','date',d,'name','Lễ')) from fixture$$,
'holiday applies atomically to all classes');
select is((select count(*)::int from pg_temp.sessions() where status='scheduled'),0,'holiday releases reservations');
select throws_ok($$select api.preview_schedule_change(a,c) from fixture,changes$$,'PT409','holiday_conflict','makeup cannot use a holiday');
select lives_ok($$select pg_temp.cmd(null,jsonb_build_object('op','remove_holiday','date',d)) from fixture$$,'removing holiday restores future sessions after confirmation');
select is((select count(*)::int from pg_temp.sessions() where status='scheduled'),4,'all future sessions restored');
select lives_ok($$select pg_temp.cmd(a,jsonb_build_object('op','weekly','appliesOn',d,'slots',jsonb_build_array(
jsonb_build_object('weekday',extract(isodow from d)::int,'startTime','14:00','endTime','15:00','roomId',null)))) from fixture$$,
'weekly revision materializes future occurrences');
create temp table occurrences as select id,starts_at,ends_at,row_version from pg_temp.sessions() where kind='weekly';
select is((select count(*)::int from occurrences),3,'weekly occurrences span the class range');
select lives_ok($$select pg_temp.cmd(x.class_id,jsonb_build_object('op','move','sessionId',x.id,'expectedVersion',x.row_version,
'date',app_private.business_date(x.starts_at),'startTime','16:00','endTime','17:00','roomId',null))
from pg_temp.sessions() x where kind='weekly' order by starts_at limit 1$$,'one session can be moved');
select lives_ok($$select pg_temp.cmd(a,jsonb_build_object('op','weekly','appliesOn',d,'slots',jsonb_build_array(
jsonb_build_object('weekday',extract(isodow from d)::int,'startTime','14:00','endTime','15:00','roomId',null)))) from fixture$$,
'replacing weekly pattern preserves exceptions');
select is((select count(*)::int from pg_temp.sessions() where kind='weekly'),3,'regeneration keeps occurrence identities without duplicates');
select is((select count(*)::int from app.business_entity_versions v left join app.class_sessions x on x.id=v.entity_id
 where v.entity_kind='class_session' and v.changed_at=now() and x.id is null),0,
'regeneration does not create history for insert proposals discarded by ON CONFLICT');
select is((select to_char(starts_at at time zone 'Asia/Ho_Chi_Minh','HH24:MI') from pg_temp.sessions() where is_exception and kind='weekly'),'16:00','manual move survives regeneration');
select lives_ok($$select api.close_class(a,'Nghỉ',1) from fixture$$,'close removes future sessions in same transaction');
select is((select count(*)::int from pg_temp.sessions() x,fixture f where x.class_id=f.a and status in ('scheduled','off','holiday')),0,'closed sessions do not reserve rooms');
select lives_ok($$select api.reopen_class(a,2) from fixture$$,'reopen restores future sessions after checks');
select is((select count(*)::int from pg_temp.sessions() x,fixture f where x.class_id=f.a and status='scheduled'),4,'reopen restores makeup and weekly occurrences');
select pg_temp.actor(3);
select throws_ok($$select api.get_class_schedule(a) from fixture$$,'PT404','not_found','an unassigned user cannot read schedule');
select pg_temp.actor(1);
select lives_ok($$select api.create_class_assignment(a,'00000000-0000-4000-8000-000000000003','assistant',d-2,d+15,null) from fixture$$,'assistant assignment fixture');
select pg_temp.actor(3);
select lives_ok($$select api.get_class_schedule(a) from fixture$$,'assigned assistant can read');
select throws_ok($$select api.preview_schedule_change(a,c) from fixture,changes$$,'PT403','forbidden','assistant cannot change schedule');
select pg_temp.actor(1);
-- Failed audit rolls back command, histories and reservations together.
create function pg_temp.fail_audit() returns trigger language plpgsql as $$ begin raise exception 'audit_failure'; end $$;
create trigger test_schedule_audit before insert on app.audit_events for each row execute function pg_temp.fail_audit();
select throws_ok($$select pg_temp.cmd(a,c||'{"startTime":"18:00","endTime":"19:00"}') from fixture,changes$$,
'P0001','audit_failure','audit failure aborts preview and mutation');
drop trigger test_schedule_audit on app.audit_events;
select is((select count(*)::int from pg_temp.sessions() where (starts_at at time zone 'Asia/Ho_Chi_Minh')::time='18:00'),0,'failed audit leaves no session');
-- Regression boundaries: manual off survives nested holiday/class states.
create temp table off_target as select x.id from pg_temp.sessions() x,fixture f where x.class_id=f.a and kind='makeup';
select pg_temp.cmd(x.class_id,jsonb_build_object('op','off','sessionId',x.id,'expectedVersion',x.row_version)) from pg_temp.sessions() x join off_target t using(id);
select pg_temp.cmd(null,jsonb_build_object('op','holiday','date',d,'name','Lễ lồng')) from fixture;
select api.close_class(a,'Đóng trong lễ',3) from fixture;
select api.reopen_class(a,4) from fixture;
select pg_temp.cmd(null,jsonb_build_object('op','remove_holiday','date',d)) from fixture;
select is((select status from pg_temp.sessions() x join off_target t using(id)),'off','holiday and reopen do not revive a manually off session');
select throws_ok($$select api.preview_schedule_change(a,jsonb_build_object('op','weekly','appliesOn',d,'slots',jsonb_build_array(
jsonb_build_object('weekday',null,'startTime','20:00','endTime','21:00','roomId',null)))) from fixture$$,
'PT400','validation_failed','direct RPC rejects NULL weekday');
select api.create_class_assignment(b,'00000000-0000-4000-8000-000000000003','teacher',d-2,d+15,null) from fixture;
insert into app.class_sessions(id,class_id,kind,original_day,original_start,starts_at,ends_at,status)
select '26000000-0000-4000-8000-000000000001',a,'makeup',d+1,'07:00',app_private.day_start(d+1)+interval '7 hours',app_private.day_start(d+1)+interval '8 hours','scheduled' from fixture;
insert into app.class_sessions(id,class_id,kind,original_day,original_start,starts_at,ends_at,status)
select '26000000-0000-4000-8000-000000000002',b,'makeup',d+1,'07:00',app_private.day_start(d+1)+interval '7 hours',app_private.day_start(d+1)+interval '8 hours','scheduled' from fixture;
select is((select count(*)::int from fixture,jsonb_array_elements(api.get_class_schedule(b)->'warnings') w where w->>'className'='Lịch B'),0,
'staff warning names the other class, regardless of session UUID ordering');
create temp table extra_room as select (api.create_room('11000000-0000-4000-8000-000000000001','Phòng lễ')->>'id')::uuid id;
select pg_temp.cmd(b,c||jsonb_build_object('roomId',r.id,'startTime','12:00','endTime','13:00')) from fixture,changes,extra_room r;
select api.close_class(b,'Đóng bù',1) from fixture;
select api.archive_room(id,'Ngừng dùng',1) from extra_room;
select throws_ok($$select api.reopen_class(b,2) from fixture$$,'PT409','invalid_state','reopen cannot reserve an archived makeup room');
create temp table reopening as select b,jsonb_build_object('op','reopen','expectedVersion',2,'adjustments',jsonb_build_array(
 jsonb_build_object('sessionId',x.id,'date',app_private.business_date(x.starts_at),'startTime','12:00','endTime','13:00','roomId',null))) change
 from fixture,pg_temp.sessions() x,extra_room r where x.class_id=b and x.room_id=r.id;
select lives_ok($$select pg_temp.cmd(b,change) from reopening$$,'reopen can review and correct a no-longer-available room atomically');
select is((select admin_state from app.classes where id=(select b from fixture)),'open','corrected reopening restores the class');
create temp table historic_room as select (api.create_room('11000000-0000-4000-8000-000000000001','Phòng lịch sử')->>'id')::uuid id;
insert into app.class_sessions(class_id,kind,original_day,original_start,starts_at,ends_at,room_id,status)
select a,'makeup',d-2,'09:00',app_private.day_start(d-2)+interval '9 hours',app_private.day_start(d-2)+interval '10 hours',r.id,'scheduled'
from fixture,historic_room r;
select pg_temp.cmd(a,c||jsonb_build_object('roomId',r.id,'startTime','21:00','endTime','22:00')) from fixture,changes,historic_room r;
select api.update_room(id,'11000000-0000-4000-8000-000000000001','Tên phòng mới',1) from historic_room;
select is((select room_name from pg_temp.sessions() where starts_at<now()),'Phòng lịch sử','renaming a room never rewrites a started session location');
select is((select room_name from pg_temp.sessions() x,historic_room r where x.room_id=r.id and starts_at>now()),'Tên phòng mới','future sessions capture updated location names');
select throws_ok($$select api.preview_schedule_change(x.class_id,jsonb_build_object('op','off','sessionId',x.id,'expectedVersion',x.row_version))
from pg_temp.sessions() x where starts_at<now()$$,'PT409','session_started','started session cannot be cancelled');
select throws_ok($$select api.preview_schedule_change(null,jsonb_build_object('op','holiday','date',d-2,'name','Lễ quá khứ')) from fixture$$,
'PT409','session_started','holiday cannot cancel started sessions');
select is((select count(*)::int from app.holidays,fixture where day=d-2),0,'blocked holiday does not leave a holiday record');
select throws_ok($$select api.preview_schedule_change(a,jsonb_build_object('op','weekly','appliesOn',d-2,'slots','[]'::jsonb)) from fixture$$,
'PT400','validation_failed','weekly revision cannot apply on a past day');
select api.close_class(a,'Chỉnh phương án tuần',5) from fixture;
select lives_ok($$select pg_temp.cmd(a,jsonb_build_object('op','reopen','expectedVersion',6,'adjustments','[]'::jsonb,
 'weekly',jsonb_build_object('appliesOn',d,'slots','[]'::jsonb))) from fixture$$,
'reopening can change the weekly plan, including future occurrences not materialized before extension');
select is((select count(*)::int from pg_temp.sessions() x,fixture f where x.class_id=f.a and x.kind='weekly' and not x.is_exception and status='scheduled'),0,
'replacement reopening pattern removes regular future occurrences while retaining exceptions');
select is((select count(*)::int from app.audit_events,fixture where action='class.reopen' and entity_refs->>'class_id'=a::text
 and before_after#>'{schedule,weekly,slots}'='[]'::jsonb and created_at=now()),1,'one reopening audit includes the reviewed schedule corrections');
create temp table scoped_preview as select a,c||'{"roomId":null,"startTime":"18:00","endTime":"19:00"}' change,
 api.preview_schedule_change(a,c||'{"roomId":null,"startTime":"18:00","endTime":"19:00"}') preview from fixture,changes;
select api.create_class('Lớp không liên quan','10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000011',
 app_private.business_date(now()),app_private.business_date(now())+20);
select lives_ok($$select api.apply_schedule_change(a,change,preview->>'token') from scoped_preview$$,
'unrelated class creation does not invalidate a reviewed class schedule');
select * from finish();
rollback;



