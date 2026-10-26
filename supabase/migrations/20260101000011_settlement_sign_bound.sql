-- Migration 11: the mediation settlement signature is bound to the text the signer was SHOWN.
-- Until now sign_settlement signed "whatever the current text is when the click arrives". The mediator (and only the mediator) can
-- reopen and edit the text while nobody has signed yet, so a party whose page was rendered before such an edit could sign a text they
-- never read. The new server-only entry point refuses unless the hash the signer saw equals the current one.
-- The old sign_settlement_srv is left untouched (existing tests call it); the application no longer uses it. Do not call it from new code.
create or replace function public.sign_settlement_bound_srv(p_actor uuid, p_aal text, p_dispute uuid, p_expected_hash text, p_ip text, p_ua text)
returns void language plpgsql security definer set search_path = public as $$
declare s public.settlements;
begin
  perform public.act_as(p_actor, p_aal);
  -- same lock order as sign_settlement (dispute, then settlement) so the text cannot change between this check and the signature
  perform 1 from public.disputes where id = p_dispute for update;
  select * into s from public.settlements where dispute_id = p_dispute for update;
  if not found or s.status <> 'pending_signatures' then raise exception 'الاتفاق غير مفتوح للتوقيع'; end if;
  if p_expected_hash is distinct from s.content_hash then
    raise exception 'تغيّر نص الاتفاق منذ عرضه عليك. حدّث الصفحة واقرأه من جديد قبل التوقيع';
  end if;
  perform public.sign_settlement(p_dispute, p_ip, p_ua);
end $$;

revoke execute on function public.sign_settlement_bound_srv(uuid, text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.sign_settlement_bound_srv(uuid, text, uuid, text, text, text) to service_role;
