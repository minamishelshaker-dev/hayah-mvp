-- Mirrors the migration already applied on the live Supabase project (hayah_12_hardening_trigger_fn_grants).
-- Trigger functions must not be callable through the REST API, and helper functions get a fixed search_path.
revoke execute on function
  public.audit_chain(), public.audit_changes(), public.audit_arb_slim(), public.audit_record_export(),
  public.audit_record_signature(), public.ensure_mediator_profile(), public.handle_new_user(), public.protect_profile(),
  public.touch_updated_at(), public.audit_immutable()
  from public, anon, authenticated;

alter function public.touch_updated_at() set search_path = public;
alter function public.audit_immutable() set search_path = public;
alter function public.mask_ip(text, boolean) set search_path = public;
alter function public.allowed_mime_types() set search_path = public;
alter function public.arb_agreement_frozen() set search_path = public;
alter function public.arb_award_frozen() set search_path = public;
