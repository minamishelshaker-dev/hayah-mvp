-- Migration 13: server-side scope exclusion (mediation agreement, article 10; constitution articles 5 and 55: "ambiguity = prohibition").
-- Labour-rights disputes that call for the government labour arbitration bodies are outside the platform. The mediator and the admin
-- still judge the other exclusions case by case. The check lives in the database, not in the form, so it cannot be bypassed.
create or replace function public.create_dispute(
  p_title text, p_description text, p_type text, p_value numeric, p_email text, p_phone text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_email text; d public.disputes; v_token text; v_agreement uuid;
begin
  perform public.check_invite_quota(auth.uid());
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_type = 'labor' then
    raise exception 'منازعات العمل خارج نطاق المنصة في هذه النسخة، فهي قد تستوجب جهات تحكيم عمالي حكومية. استشر محاميًا';
  end if;
  select id into v_agreement from public.legal_documents where kind = 'mediation_agreement' and is_current;
  if v_agreement is null then raise exception 'لا توجد اتفاقية وساطة منشورة'; end if;
  select email into v_email from public.profiles where id = v_uid;
  if lower(trim(p_email)) = lower(v_email) then
    raise exception 'لا يمكنك دعوة نفسك كطرف ثانٍ في النزاع';
  end if;
  insert into public.disputes (title, description, dispute_type, dispute_value_egp, created_by, claimant_id, agreement_document_id)
  values (p_title, p_description, p_type, p_value, v_uid, v_uid, v_agreement) returning * into d;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (dispute_id, invited_email, invited_phone, token, expires_at)
  values (d.id, lower(trim(p_email)), nullif(trim(p_phone), ''), v_token, now() + interval '7 days');
  return jsonb_build_object('id', d.id, 'dispute_number', d.dispute_number, 'token', v_token);
end $$;
