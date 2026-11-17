-- Migration 17: kinds of legal documents and how each one reaches the user.
--   registration : accepted at sign-up, one explicit acknowledgment per document (they never include a consent to mediation or arbitration)
--   public       : published for everyone to read, nothing to accept
--   dispute      : accepted inside a mediation file, by each party, for that file only
--   arbitration  : accepted inside an arbitration file, by each party, for that file only
-- Signing up is therefore kept completely apart from consenting to any procedure.

alter table public.legal_documents drop constraint legal_documents_kind_check;

create table public.legal_kinds (
  kind text primary key,
  scope text not null check (scope in ('registration', 'public', 'dispute', 'arbitration')),
  position integer not null,
  short_title text not null
);
insert into public.legal_kinds (kind, scope, position, short_title) values
  ('terms', 'registration', 1, 'شروط الاستخدام'),
  ('privacy', 'registration', 2, 'سياسة الخصوصية'),
  ('acceptable_use', 'registration', 3, 'سياسة الاستخدام المقبول'),
  ('disclaimer', 'registration', 4, 'إخلاء المسؤولية'),
  ('esign_notice', 'registration', 5, 'إشعار التوقيع الإلكتروني'),
  ('cookies', 'public', 10, 'ملفات تعريف الارتباط'),
  ('retention', 'public', 11, 'الاحتفاظ بالبيانات ومحوها'),
  ('security', 'public', 12, 'أمن المعلومات والإبلاغ عن الحوادث'),
  ('ai_policy', 'public', 13, 'الذكاء الاصطناعي والإشراف البشري'),
  ('complaints', 'public', 14, 'الشكاوى'),
  ('fees', 'public', 15, 'الرسوم وأتعاب المحايدين'),
  ('admission', 'public', 16, 'قبول ورفض المنازعات'),
  ('exclusions', 'public', 17, 'المسائل المستبعدة أو المقبولة بشروط'),
  ('conduct', 'public', 18, 'مدونة سلوك الوسطاء والمحكمين والخبراء'),
  ('conflicts', 'public', 19, 'الإفصاح وتعارض المصالح والتنحي والرد'),
  ('statistics', 'public', 20, 'نشر الإحصاءات والأحكام'),
  ('mediation_agreement', 'dispute', 30, 'اتفاقية الوساطة'),
  ('arbitration_rules', 'arbitration', 31, 'قواعد التحكيم السريع');

alter table public.legal_documents add constraint legal_documents_kind_fk foreign key (kind) references public.legal_kinds (kind);
alter table public.legal_kinds enable row level security;
create policy legal_kinds_select on public.legal_kinds for select to anon, authenticated using (true);
grant select on public.legal_kinds to anon, authenticated;
revoke insert, update, delete, truncate on public.legal_kinds from anon, authenticated;

-- the platform gate: every CURRENT registration-scope document must have been accepted by the signed-in user
create or replace function public.has_platform_consent() returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.legal_documents l join public.legal_kinds k on k.kind = l.kind
     where l.is_current and k.scope = 'registration'
       and not exists (select 1 from public.consents c where c.document_id = l.id and c.user_id = auth.uid()));
$$;

-- public reading of the current texts (no sign-in needed)
create or replace function public.legal_public() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', l.kind, 'scope', k.scope, 'position', k.position, 'short_title', k.short_title,
           'title', l.title, 'version', l.version, 'published_at', l.created_at, 'body_hash', l.body_hash, 'body', l.body) order by k.position), '[]'::jsonb)
    from public.legal_documents l join public.legal_kinds k on k.kind = l.kind
   where l.is_current and not l.is_placeholder;
$$;
revoke execute on function public.legal_public() from public;
grant execute on function public.legal_public() to anon, authenticated;
