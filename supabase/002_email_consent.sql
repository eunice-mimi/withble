-- =====================================================================
-- 002: 동의 기록에 "이메일(선택)" 항목 추가
--
-- 이유: Supabase의 카카오 로그인은 이메일을 항상 함께 요청해서(KOE205),
--       카카오 비즈 앱으로 전환하고 이메일을 선택 동의로 받기로 함.
-- 실행: SQL Editor > New query 에 붙여넣고 Run. 한 번만 실행.
-- =====================================================================

begin;

alter table public.consents drop constraint consents_item_check;
alter table public.consents add constraint consents_item_check
  check (item in ('age14', 'collect', 'sensitive', 'overseas', 'photo', 'email'));

commit;
