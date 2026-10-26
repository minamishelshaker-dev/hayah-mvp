\set ON_ERROR_STOP 1
\pset tuples_only on
\pset format unaligned

drop schema if exists t cascade;
create schema t;
grant usage on schema t to public;
-- migration 10 removed the default EXECUTE-for-everyone on new functions; the test helpers live in their own schema and need it.
alter default privileges in schema t grant execute on functions to public;

create function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', msg; end if;
  raise notice 'PASS: %', msg;
end $$;

-- Runs q and requires it to fail (optionally with a message containing pat).
create function t.fails(q text, msg text, pat text default null) returns void language plpgsql as $$
declare v_err text;
begin
  begin execute q; exception when others then v_err := sqlerrm; end;
  if v_err is null then raise exception 'FAIL (no error raised): %', msg; end if;
  if pat is not null and position(pat in v_err) = 0 then
    raise exception 'FAIL (wrong error "%"): %', v_err, msg;
  end if;
  raise notice 'PASS: %', msg;
end $$;

create function t.as_user(u uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', u::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'aal', aal)::text, false);
  perform set_config('app.t_user', u::text, false);
  perform set_config('app.t_aal', aal, false);
  set role authenticated;
end $$;
create function t.as_anon() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', '', false); perform set_config('request.jwt.claims', '', false); set role anon; end $$;
create function t.as_service() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', '', false); perform set_config('request.jwt.claims', '', false); set role service_role; end $$;
create function t.as_super() returns void language plpgsql as $$
begin reset role; perform set_config('request.jwt.claim.sub', '', false); perform set_config('request.jwt.claims', '', false); end $$;


-- ---- "the server": evidence writes go through service-only functions, acting as the current test user.
create function t.accept_legal(p_doc uuid, p_dispute uuid, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.accept_legal_srv(u, a, p_doc, p_dispute, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;

create function t.sign_settlement(p_dispute uuid, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.sign_settlement_srv(u, a, p_dispute, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;

create function t.accept_platform() returns void language plpgsql as $$
declare r record;
begin
  for r in select id from public.legal_documents where kind in ('terms', 'privacy') and is_current loop
    perform t.accept_legal(r.id, null, 'ip', 'ua');
  end loop;
end $$;

-- A file "uploaded" to storage (done by the browser in real life).
create function t.put_object(p_path text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role;
  insert into storage.objects (bucket_id, name) values ('documents', p_path);
  perform t.as_user(u, a);
end $$;

create function t.register_document(p_dispute uuid, p_name text, p_path text, p_mime text, p_size bigint, p_hash text, p_type text default 'evidence')
returns uuid language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal'); v uuid;
begin
  reset role; set role service_role;
  v := public.register_document_srv(u, a, p_dispute, p_path, p_name, p_mime, p_size, p_hash, p_type);
  perform t.as_user(u, a);
  return v;
end $$;

-- ---- arbitration: evidence writes by "the server", acting as the current test user
create function t.accept_arb_rules(p_doc uuid, p_arb uuid, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.accept_arb_rules_srv(u, a, p_doc, p_arb, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;

-- accepts the rules version pinned to the arbitration
create function t.accept_rules(p_arb uuid) returns void language plpgsql as $$
begin perform t.accept_arb_rules((public.arb_gate_info(p_arb)->'doc'->>'id')::uuid, p_arb, 'ip', 'ua'); end $$;

create function t.confirm_arb_agreement(p_arb uuid, p_doc uuid, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.confirm_arb_agreement_srv(u, a, p_arb, p_doc, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;

create function t.register_arb_document(p_arb uuid, p_name text, p_path text, p_mime text, p_size bigint, p_hash text, p_type text)
returns uuid language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal'); v uuid;
begin
  reset role; set role service_role;
  v := public.register_arb_document_srv(u, a, p_arb, p_path, p_name, p_mime, p_size, p_hash, p_type);
  perform t.as_user(u, a);
  return v;
end $$;

-- ---- migration 10: signing on the platform, acting as the current test user
create function t.sign_arb_agreement(p_arb uuid, p_hash text, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.sign_arb_agreement_srv(u, a, p_arb, p_hash, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;

create function t.sign_award(p_arb uuid, p_hash text, p_date date, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.sign_award_srv(u, a, p_arb, p_hash, p_date, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;

create function t.attach_arb_signature(p_kind text, p_arb uuid, p_sig text, p_key text) returns void language plpgsql as $$
declare u text := current_setting('app.t_user', true); a text := current_setting('app.t_aal', true);
begin
  reset role; set role service_role;
  perform public.attach_arb_signature(p_kind, p_arb, p_sig, p_key);
  reset role;
  if u is not null and u <> '' then perform t.as_user(u::uuid, a); end if;
end $$;

-- ---- migration 11: settlement signature bound to the shown hash
create function t.sign_settlement_bound(p_dispute uuid, p_hash text, p_ip text, p_ua text) returns void language plpgsql as $$
declare u uuid := current_setting('app.t_user')::uuid; a text := current_setting('app.t_aal');
begin
  reset role; set role service_role;
  perform public.sign_settlement_bound_srv(u, a, p_dispute, p_hash, p_ip, p_ua);
  perform t.as_user(u, a);
end $$;
