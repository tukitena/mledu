-- GĐ 0 Auth/audit spike schema — REFERENCE ONLY, NOT A MIGRATION.
--
-- Exported on 2026-10-27 (read-only) from the local `mledu` Supabase stack that
-- ran the GĐ 0 spike, because the spike migrations were removed during the GĐ 0
-- cleanup. Kept so the spike tests in apps/api/tests can be re-run and the design
-- can be carried into GĐ 2 (G1-05). See docs/developer/decisions/auth-audit*.md.
--
-- Never apply this to staging/production. To re-run the spike on a throwaway
-- local stack: apply this file (npm run spike:db), expose the `public` schema and
-- enable the access token hook shown in supabase/config.toml, then
-- npm run test:auth:integration.

--
-- PostgreSQL database dump
--

\restrict FRMU2syEDhrVbJv5u0TY3t3Cd8B94L6Npv1NgCDsAejyOcU6epm8nzC1t5jqWf5

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11


--
-- Name: spike_private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA spike_private;


--
-- Name: access_token_hook(jsonb); Type: FUNCTION; Schema: spike_private; Owner: -
--

CREATE FUNCTION spike_private.access_token_hook(event jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_account spike_private.accounts; v_session uuid;
begin
  select * into v_account from spike_private.accounts where user_id=(event->>'user_id')::uuid;
  if not found or not v_account.auth_controlled then return event; end if;
  if v_account.status<>'active' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Account unavailable'));
  end if;
  v_session := (event->'claims'->>'session_id')::uuid;
  if exists (select 1 from auth.sessions where id=v_session and created_at<=v_account.revoked_before)
    or ((event->>'authentication_method')='token_refresh' and not exists (
      select 1 from auth.sessions where id=v_session and user_id=v_account.user_id and created_at>v_account.revoked_before
    )) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'Session revoked'));
  end if;
  return event;
end;
$$;




--
-- Name: accounts; Type: TABLE; Schema: spike_private; Owner: -
--

CREATE TABLE spike_private.accounts (
    user_id uuid NOT NULL,
    email text NOT NULL,
    role text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    must_change_password boolean DEFAULT true NOT NULL,
    revoked_before timestamp with time zone DEFAULT '-infinity'::timestamp with time zone NOT NULL,
    auth_controlled boolean DEFAULT false NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    CONSTRAINT accounts_email_check CHECK ((email = lower(btrim(email)))),
    CONSTRAINT accounts_role_check CHECK ((role = ANY (ARRAY['Admin'::text, 'Receptionist'::text, 'User'::text]))),
    CONSTRAINT accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deleted'::text])))
);


--
-- Name: actor(boolean); Type: FUNCTION; Schema: spike_private; Owner: -
--

CREATE FUNCTION spike_private.actor(p_allow_temporary boolean DEFAULT false) RETURNS spike_private.accounts
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_actor spike_private.accounts;
begin
  select * into v_actor from spike_private.accounts where user_id = auth.uid();
  if not found or v_actor.status <> 'active' then
    raise exception 'ACCOUNT_UNAVAILABLE' using errcode = '42501';
  end if;
  if not exists (
    select 1 from auth.sessions s
    where s.id = (auth.jwt()->>'session_id')::uuid
      and s.user_id = v_actor.user_id and s.created_at > v_actor.revoked_before
  ) then
    raise exception 'SESSION_REVOKED' using errcode = '42501';
  end if;
  if v_actor.must_change_password and not p_allow_temporary then
    raise exception 'PASSWORD_CHANGE_REQUIRED' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;


--
-- Name: bump_account_version(); Type: FUNCTION; Schema: spike_private; Owner: -
--

CREATE FUNCTION spike_private.bump_account_version() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin new.version := old.version + 1; return new; end;
$$;


--
-- Name: complete_auth_command(); Type: FUNCTION; Schema: spike_private; Owner: -
--

CREATE FUNCTION spike_private.complete_auth_command() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare
  v_target spike_private.accounts;
  v_actor spike_private.accounts;
  v_command spike_private.auth_commands;
  v_command_id text;
  v_before jsonb;
  v_after jsonb;
  v_password_changed boolean := new.encrypted_password is distinct from old.encrypted_password;
  v_ban_changed boolean := new.banned_until is distinct from old.banned_until;
begin
  select * into v_target from spike_private.accounts where user_id=new.id for update;
  if not found or not v_target.auth_controlled then return null; end if;
  select raw_app_meta_data->>'spike_auth_command' into v_command_id from auth.users where id=new.id;
  if v_command_id is null or v_command_id !~ '^[0-9a-f-]{36}$' then
    raise exception 'AUTH_COMMAND_REQUIRED' using errcode='42501';
  end if;
  select * into v_command from spike_private.auth_commands where id=v_command_id::uuid for update;
  if not found or v_command.target_id<>new.id or v_command.consumed_at is not null
    or v_command.expires_at <= clock_timestamp() or v_command.expected_version<>v_target.version then
    raise exception 'AUTH_COMMAND_INVALID' using errcode='42501';
  end if;
  select * into v_actor from spike_private.accounts where user_id=v_command.actor_id for share;
  if not found or v_actor.role<>'Admin' or v_actor.status<>'active' or v_actor.must_change_password
    or v_target.role='Admin' then
    raise exception 'AUTH_ACTOR_REVOKED' using errcode='42501';
  end if;
  perform 1 from auth.sessions s where s.id=v_command.actor_session
    and s.user_id=v_actor.user_id and s.created_at>v_actor.revoked_before for share;
  if not found then raise exception 'AUTH_ACTOR_REVOKED' using errcode='42501'; end if;
  v_before := to_jsonb(v_target);
  if v_command.action='disable' and v_ban_changed and not v_password_changed
    and new.banned_until > clock_timestamp() and v_target.status='active' then
    update spike_private.accounts set status='disabled', revoked_before=clock_timestamp() where user_id=new.id;
  elsif v_command.action='enable' and v_ban_changed and not v_password_changed
    and new.banned_until is null and v_target.status='disabled' then
    update spike_private.accounts set status='active', revoked_before=clock_timestamp() where user_id=new.id;
  elsif v_command.action='set_temporary_password' and v_password_changed and not v_ban_changed
    and v_target.status='active' then
    update spike_private.accounts set must_change_password=true, revoked_before=clock_timestamp() where user_id=new.id;
  else raise exception 'AUTH_COMMAND_MISMATCH' using errcode='42501'; end if;
  select to_jsonb(a) into v_after from spike_private.accounts a where user_id=new.id;
  insert into spike_private.audit_log(actor_id, target_id, action, before_data, after_data, command_id)
    values(v_actor.user_id, new.id, v_command.action, v_before, v_after, v_command.id);
  update spike_private.auth_commands set consumed_at=clock_timestamp() where id=v_command.id;
  return null;
end;
$_$;


--
-- Name: audit_log; Type: TABLE; Schema: spike_private; Owner: -
--

CREATE TABLE spike_private.audit_log (
    id bigint NOT NULL,
    actor_id uuid NOT NULL,
    target_id uuid NOT NULL,
    action text NOT NULL,
    before_data jsonb,
    after_data jsonb,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    command_id uuid
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: spike_private; Owner: -
--

ALTER TABLE spike_private.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME spike_private.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_commands; Type: TABLE; Schema: spike_private; Owner: -
--

CREATE TABLE spike_private.auth_commands (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid NOT NULL,
    actor_session uuid NOT NULL,
    target_id uuid NOT NULL,
    action text NOT NULL,
    expected_version bigint NOT NULL,
    request_id uuid NOT NULL,
    expires_at timestamp with time zone DEFAULT (clock_timestamp() + '00:01:00'::interval) NOT NULL,
    consumed_at timestamp with time zone,
    CONSTRAINT auth_commands_action_check CHECK ((action = ANY (ARRAY['disable'::text, 'enable'::text, 'set_temporary_password'::text])))
);


--
-- Name: accounts accounts_email_key; Type: CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.accounts
    ADD CONSTRAINT accounts_email_key UNIQUE (email);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (user_id);


--
-- Name: audit_log audit_log_command_id_key; Type: CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.audit_log
    ADD CONSTRAINT audit_log_command_id_key UNIQUE (command_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: auth_commands auth_commands_actor_id_request_id_key; Type: CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.auth_commands
    ADD CONSTRAINT auth_commands_actor_id_request_id_key UNIQUE (actor_id, request_id);


--
-- Name: auth_commands auth_commands_pkey; Type: CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.auth_commands
    ADD CONSTRAINT auth_commands_pkey PRIMARY KEY (id);


--
-- Name: accounts bump_account_version; Type: TRIGGER; Schema: spike_private; Owner: -
--

CREATE TRIGGER bump_account_version BEFORE UPDATE ON spike_private.accounts FOR EACH ROW EXECUTE FUNCTION spike_private.bump_account_version();


--
-- Name: accounts accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.accounts
    ADD CONSTRAINT accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: auth_commands auth_commands_actor_id_fkey; Type: FK CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.auth_commands
    ADD CONSTRAINT auth_commands_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: auth_commands auth_commands_target_id_fkey; Type: FK CONSTRAINT; Schema: spike_private; Owner: -
--

ALTER TABLE ONLY spike_private.auth_commands
    ADD CONSTRAINT auth_commands_target_id_fkey FOREIGN KEY (target_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: accounts; Type: ROW SECURITY; Schema: spike_private; Owner: -
--

ALTER TABLE spike_private.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: spike_private; Owner: -
--

ALTER TABLE spike_private.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: auth_commands; Type: ROW SECURITY; Schema: spike_private; Owner: -
--

ALTER TABLE spike_private.auth_commands ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA spike_private; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA spike_private TO supabase_auth_admin;


--
-- Name: FUNCTION access_token_hook(event jsonb); Type: ACL; Schema: spike_private; Owner: -
--

REVOKE ALL ON FUNCTION public.spike_private.access_token_hook(event jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION spike_private.access_token_hook(event jsonb) TO supabase_auth_admin;


--
-- Name: FUNCTION actor(p_allow_temporary boolean); Type: ACL; Schema: spike_private; Owner: -
--

REVOKE ALL ON FUNCTION public.spike_private.actor(p_allow_temporary boolean) FROM PUBLIC;


--
-- Name: FUNCTION bump_account_version(); Type: ACL; Schema: spike_private; Owner: -
--

REVOKE ALL ON FUNCTION public.spike_private.bump_account_version() FROM PUBLIC;


--
-- Name: FUNCTION complete_auth_command(); Type: ACL; Schema: spike_private; Owner: -
--

REVOKE ALL ON FUNCTION public.spike_private.complete_auth_command() FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict FRMU2syEDhrVbJv5u0TY3t3Cd8B94L6Npv1NgCDsAejyOcU6epm8nzC1t5jqWf5


-- Public RPC entry points used by the spike API (apps/api/src/spike-app.ts).
CREATE OR REPLACE FUNCTION public.spike_auth_command_result(p_command uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor spike_private.accounts; v_command spike_private.auth_commands; v_target spike_private.accounts; v_banned boolean;
begin
  v_actor := spike_private.actor();
  select * into v_command from spike_private.auth_commands where id=p_command;
  if not found or v_command.actor_id<>v_actor.user_id or v_actor.role<>'Admin' then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if v_command.consumed_at is not null then return jsonb_build_object('committed', true, 'changed', true); end if;
  select * into v_target from spike_private.accounts where user_id=v_command.target_id;
  select coalesce(banned_until > clock_timestamp(), false) into v_banned from auth.users where id=v_command.target_id;
  if v_target.version > v_command.expected_version and
    ((v_command.action='disable' and v_target.status='disabled' and v_banned)
      or (v_command.action='enable' and v_target.status='active' and not v_banned)) then
    return jsonb_build_object('committed', true, 'changed', false);
  end if;
  return jsonb_build_object('committed', false);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.spike_business()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor spike_private.accounts;
begin
  v_actor := spike_private.actor();
  return jsonb_build_object('allowed', true, 'role', v_actor.role);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.spike_identity()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor spike_private.accounts;
begin
  v_actor := spike_private.actor(true);
  return jsonb_build_object('id', v_actor.user_id, 'role', v_actor.role,
    'mustChangePassword', v_actor.must_change_password);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.spike_prepare_auth_command(p_target uuid, p_action text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor spike_private.accounts;
  v_target spike_private.accounts;
  v_command spike_private.auth_commands;
  v_banned boolean;
begin
  v_actor := spike_private.actor();
  if v_actor.role <> 'Admin' then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
  if p_action is null or p_action not in ('disable', 'enable', 'set_temporary_password') then
    raise exception 'INVALID_ACTION' using errcode = '22023';
  end if;
  select * into v_target from spike_private.accounts where user_id=p_target for update;
  if not found then raise exception 'NOT_FOUND' using errcode = 'P0002'; end if;
  if v_target.role='Admin' then raise exception 'ADMIN_MANAGEMENT_FORBIDDEN' using errcode='42501'; end if;
  if not v_target.auth_controlled then raise exception 'AUTH_BRIDGE_NOT_ENABLED' using errcode='0A000'; end if;
  if v_target.status='deleted' then raise exception 'INVALID_STATE' using errcode='PT409'; end if;
  select coalesce(banned_until > clock_timestamp(), false) into v_banned from auth.users where id=p_target;
  if (p_action='disable' and v_target.status='disabled' and v_banned)
    or (p_action='enable' and v_target.status='active' and not v_banned) then
    return jsonb_build_object('changed', false);
  end if;
  if (p_action='disable' and (v_target.status<>'active' or v_banned))
    or (p_action='enable' and (v_target.status<>'disabled' or not v_banned))
    or (p_action='set_temporary_password' and (v_target.status<>'active' or v_banned)) then
    raise exception 'AUTH_STATE_CONFLICT' using errcode='PT409';
  end if;
  select * into v_command from spike_private.auth_commands where actor_id=v_actor.user_id and request_id=p_request_id;
  if found then
    if v_command.target_id<>p_target or v_command.action<>p_action then
      raise exception 'REQUEST_CONFLICT' using errcode='PT409';
    end if;
  else
    insert into spike_private.auth_commands(actor_id, actor_session, target_id, action, expected_version, request_id)
      values(v_actor.user_id, (auth.jwt()->>'session_id')::uuid, p_target, p_action, v_target.version, p_request_id)
      returning * into v_command;
  end if;
  return jsonb_build_object('changed', true, 'commandId', v_command.id);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.spike_reception()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor spike_private.accounts;
begin
  v_actor := spike_private.actor();
  if v_actor.role not in ('Admin', 'Receptionist') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return jsonb_build_object('allowed', true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.spike_set_account(p_target uuid, p_operation text, p_role text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_operation is distinct from 'set_role' then
    raise exception 'USE_AUTH_STATUS_COMMAND' using errcode='42501';
  end if;
  return public.spike_set_account_legacy(p_target, p_operation, p_role);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.spike_set_account_legacy(p_target uuid, p_operation text, p_role text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor spike_private.accounts;
  v_before spike_private.accounts;
  v_after spike_private.accounts;
begin
  v_actor := spike_private.actor();
  if v_actor.role <> 'Admin' then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select * into v_before from spike_private.accounts where user_id = p_target for update;
  if not found then raise exception 'NOT_FOUND' using errcode = 'P0002'; end if;
  if v_before.role = 'Admin' then
    raise exception 'ADMIN_MANAGEMENT_FORBIDDEN' using errcode = '42501';
  end if;
  if p_operation = 'disable' then
    if v_before.status = 'deleted' then raise exception 'INVALID_STATE'; end if;
    if v_before.status = 'disabled' then return jsonb_build_object('changed', false); end if;
    update spike_private.accounts set status = 'disabled', revoked_before = clock_timestamp()
      where user_id = p_target;
  elsif p_operation = 'enable' then
    if v_before.status <> 'disabled' then raise exception 'INVALID_STATE'; end if;
    -- Also reject Auth sessions created while the application account was disabled.
    update spike_private.accounts set status = 'active', revoked_before = clock_timestamp()
      where user_id = p_target;
  elsif p_operation = 'set_role' then
    if p_role is null or p_role not in ('User', 'Receptionist') then
      raise exception 'INVALID_ROLE' using errcode = '22023';
    end if;
    if v_before.status <> 'active' then raise exception 'INVALID_STATE'; end if;
    if v_before.role = p_role then return jsonb_build_object('changed', false); end if;
    if v_before.role = 'User' and p_role = 'Receptionist' then
      raise exception 'ASSIGNMENT_CHECK_REQUIRED' using errcode = '0A000';
    end if;
    update spike_private.accounts set role = p_role where user_id = p_target;
  else
    raise exception 'INVALID_OPERATION' using errcode = '22023';
  end if;
  select * into v_after from spike_private.accounts where user_id = p_target;
  insert into spike_private.audit_log(actor_id, target_id, action, before_data, after_data)
    values (v_actor.user_id, p_target, p_operation, to_jsonb(v_before), to_jsonb(v_after));
  return jsonb_build_object('changed', true);
end;
$function$
;
REVOKE ALL ON FUNCTION public.spike_auth_command_result(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spike_business() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spike_identity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spike_prepare_auth_command(uuid,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spike_reception() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spike_set_account_legacy(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.spike_set_account(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spike_auth_command_result(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.spike_auth_command_result(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.spike_business() TO authenticated;
GRANT EXECUTE ON FUNCTION public.spike_business() TO service_role;
GRANT EXECUTE ON FUNCTION public.spike_identity() TO authenticated;
GRANT EXECUTE ON FUNCTION public.spike_identity() TO service_role;
GRANT EXECUTE ON FUNCTION public.spike_prepare_auth_command(uuid,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.spike_prepare_auth_command(uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.spike_reception() TO authenticated;
GRANT EXECUTE ON FUNCTION public.spike_reception() TO service_role;
GRANT EXECUTE ON FUNCTION public.spike_set_account(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.spike_set_account(uuid,text,text) TO service_role;

-- Ties GoTrue updates of auth.users to the spike command/audit (deferred, same transaction).
CREATE CONSTRAINT TRIGGER spike_complete_auth_command AFTER UPDATE ON auth.users DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((((old.encrypted_password)::text IS DISTINCT FROM (new.encrypted_password)::text) OR (old.banned_until IS DISTINCT FROM new.banned_until))) EXECUTE FUNCTION spike_private.complete_auth_command();
