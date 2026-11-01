-- =====================================================================
-- 윗블 보안 규칙 시험
--
-- 실행 방법: 001_schema.sql을 실행한 뒤, SQL Editor에 이 파일 전체를 붙여넣고 Run.
--   - 성공: 결과에 "모든 보안 시험 통과"가 나온다.
--   - 실패: "시험 실패: ..." 오류가 나오고 멈춘다.
--   - 가짜 사용자와 글은 마지막에 모두 되돌려서(rollback) 실제 데이터는 남지 않는다.
--
-- 등장인물
--   미미(U1): 사랑셀 모임장    영희(U2): 초대받아 들어온 멤버
--   철수(U3): 모임 밖 사람      U4: 닉네임이 긴 사용자 (12자로 잘리는지)
-- =====================================================================

begin;

-- 가짜 사용자 만들기 (카카오 로그인 대신 직접 넣음)
insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-4000-8000-000000000001', '{"name": "미미", "avatar_url": "https://k.kakaocdn.net/a.jpg"}'),
  ('00000000-0000-4000-8000-000000000002', '{"name": "영희"}'),
  ('00000000-0000-4000-8000-000000000003', '{"name": "철수", "avatar_url": "javascript:alert(1)"}'),
  ('00000000-0000-4000-8000-000000000004', '{"nickname": "열두글자보다훨씬더긴카카오닉네임"}');

do $$ begin
  assert (select count(*) from public.profiles where id::text like '00000000-0000-4000-8000-00000000000_') = 4,
    '시험 실패: 가입하면 프로필이 자동으로 만들어져야 함';
  assert (select count(*) from public.user_settings where user_id::text like '00000000-0000-4000-8000-00000000000_') = 4,
    '시험 실패: 가입하면 설정이 자동으로 만들어져야 함';
  assert (select char_length(name) from public.profiles where id = '00000000-0000-4000-8000-000000000004') = 12,
    '시험 실패: 긴 닉네임은 12자로 잘려야 함';
  assert (select avatar_url from public.profiles where id = '00000000-0000-4000-8000-000000000003') is null,
    '시험 실패: https가 아닌 프로필 사진 주소는 저장하면 안 됨';
end $$;

-- ---------------------------------------------------------------------
-- 1. 미미: 사랑셀을 만들고 초대 코드를 만든다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;

select set_config('test.gid', public.create_group('사랑셀', '셀/목장', '금요일 저녁 셀')::text, true);
select set_config('test.code', public.create_invite(current_setting('test.gid')::uuid), true);

do $$
declare gid uuid := current_setting('test.gid')::uuid;
begin
  assert (select role from public.group_members where group_id = gid) = 'leader',
    '시험 실패: 모임을 만든 사람은 모임장이어야 함';
  assert current_setting('test.code') ~ '^[A-Z0-9]{8}$', '시험 실패: 초대 코드는 8자리여야 함';
  assert (select count(*) from public.groups) = 1, '시험 실패: 미미는 자기 모임을 볼 수 있어야 함';
  begin
    insert into public.groups (name) values ('몰래 만든 모임');
    assert false, '시험 실패: 함수 없이 모임을 직접 만들 수 있으면 안 됨';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 2. 철수(모임 밖 사람): 아무것도 볼 수 없고, 끼어들 수 없다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;

do $$
declare gid uuid := current_setting('test.gid')::uuid;
begin
  assert (select count(*) from public.groups) = 0, '시험 실패: 철수가 남의 모임을 볼 수 있음';
  assert (select count(*) from public.group_members) = 0, '시험 실패: 철수가 남의 모임 명단을 볼 수 있음';
  assert (select count(*) from public.invites) = 0, '시험 실패: 철수가 남의 초대 코드를 볼 수 있음';
  assert (select count(*) from public.profiles) = 1, '시험 실패: 철수는 자기 프로필만 봐야 함';
  assert (select count(*) from public.invite_preview('ZZZZZZZZ')) = 0, '시험 실패: 없는 초대 코드로 모임 정보가 보임';

  begin
    perform public.create_invite(gid);
    assert false, '시험 실패: 멤버가 아닌데 초대 코드를 만들 수 있음';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.prayers (title, group_id) values ('끼어들기', gid);
    assert false, '시험 실패: 멤버가 아닌데 모임에 기도제목을 올릴 수 있음';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.group_members (group_id, user_id) values (gid, '00000000-0000-4000-8000-000000000003');
    assert false, '시험 실패: 초대 없이 멤버로 직접 들어갈 수 있음';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 3. 영희: 초대 코드로 들어와서 글을 쓴다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;

do $$
declare
  gid uuid := current_setting('test.gid')::uuid;
  pid uuid;
  p record;
begin
  select * into p from public.invite_preview(current_setting('test.code'));
  assert p.name = '사랑셀' and p.member_count = 1 and not p.already_member,
    '시험 실패: 초대 미리보기에 모임 이름과 인원수가 나와야 함';

  assert public.join_group(lower(current_setting('test.code'))) = gid, '시험 실패: 초대 코드로 가입해야 함';
  assert (select role from public.group_members where user_id = '00000000-0000-4000-8000-000000000002') = 'member',
    '시험 실패: 초대로 들어오면 일반 멤버여야 함';
  assert (select count(*) from public.group_members where group_id = gid) = 2, '시험 실패: 멤버 명단이 보여야 함';

  insert into public.prayers (title, body, group_id) values ('부모님 건강', '검사 결과를 기다려요', gid)
  returning id into pid;
  perform set_config('test.pid', pid::text, true);
  insert into public.prayers (title) values ('나만 아는 기도');
  insert into public.meditations (body, group_id, ref_book, ref_chapter, ref_verses) values ('목자 되신 주님', gid, 18, 23, '{1}');
  insert into public.highlights (book, chapter, verse) values (18, 23, 1);
  insert into public.consents (item, version, agreed) values ('sensitive', 'v0.1', true);
  insert into public.consents (item, version, agreed) values ('email', 'v0.1', false);

  begin
    insert into public.consents (user_id, item, version, agreed)
    values ('00000000-0000-4000-8000-000000000001', 'collect', 'v0.1', true);
    assert false, '시험 실패: 남의 이름으로 동의 기록을 넣을 수 있음';
  exception when insufficient_privilege then null;
  end;

  -- 일반 멤버는 다른 멤버를 내보내거나 모임 정보를 바꿀 수 없다
  delete from public.group_members where user_id = '00000000-0000-4000-8000-000000000001';
  update public.groups set name = '영희셀';
  assert (select count(*) from public.group_members where group_id = gid) = 2, '시험 실패: 일반 멤버가 모임장을 내보냄';
  assert (select name from public.groups where id = gid) = '사랑셀', '시험 실패: 일반 멤버가 모임 이름을 바꿈';
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 4. 미미: 영희의 모임 글은 보이지만, 나만 보기 글과 개인 기록은 안 보인다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;

do $$
declare
  pid uuid := current_setting('test.pid')::uuid;
  n int;
begin
  assert (select count(*) from public.prayers where author_id = '00000000-0000-4000-8000-000000000002') = 1,
    '시험 실패: 미미에게 영희의 모임 기도 1개만 보여야 함 (나만 보기는 안 보여야 함)';
  assert (select count(*) from public.meditations) = 1, '시험 실패: 미미에게 영희의 모임 묵상이 보여야 함';
  assert (select count(*) from public.profiles where id = '00000000-0000-4000-8000-000000000002') = 1,
    '시험 실패: 같은 모임 멤버의 프로필은 보여야 함';
  assert (select count(*) from public.highlights) = 0, '시험 실패: 남의 하이라이트가 보임';
  assert (select count(*) from public.user_settings) = 1, '시험 실패: 남의 설정이 보임';
  assert (select count(*) from public.consents) = 0, '시험 실패: 남의 동의 기록이 보임';

  insert into public.reactions (prayer_id) values (pid);  -- 함께 기도
  assert (select count(*) from public.reactions) = 1, '시험 실패: 모임 글에 반응할 수 있어야 함';

  update public.prayers set title = '바꿔치기' where id = pid;
  get diagnostics n = row_count;
  assert n = 0, '시험 실패: 남의 기도제목을 고칠 수 있음';
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 5. 철수: 여전히 아무 글도, 반응도 볼 수 없고 고칠 수도 없다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;

do $$
declare
  pid uuid := current_setting('test.pid')::uuid;
  n int;
begin
  assert (select count(*) from public.prayers) = 0, '시험 실패: 철수가 남의 기도제목을 볼 수 있음';
  assert (select count(*) from public.meditations) = 0, '시험 실패: 철수가 남의 묵상을 볼 수 있음';
  assert (select count(*) from public.reactions) = 0, '시험 실패: 철수가 남의 반응을 볼 수 있음';
  assert (select count(*) from public.profiles) = 1, '시험 실패: 철수가 모르는 사람의 프로필을 볼 수 있음';

  update public.prayers set status = 'answered' where id = pid;
  get diagnostics n = row_count;
  assert n = 0, '시험 실패: 철수가 남의 기도제목을 고칠 수 있음';
  delete from public.prayers where id = pid;
  get diagnostics n = row_count;
  assert n = 0, '시험 실패: 철수가 남의 기도제목을 지울 수 있음';
  begin
    insert into public.reactions (prayer_id) values (pid);
    assert false, '시험 실패: 볼 수 없는 글에 반응할 수 있음';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 6. 로그인하지 않은 사람: 표도 함수도 쓸 수 없다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"role": "anon"}', true);
set local role anon;

do $$ begin
  begin
    perform count(*) from public.prayers;
    assert false, '시험 실패: 로그인하지 않은 사람이 기도제목 표에 접근할 수 있음';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.profiles;
    assert false, '시험 실패: 로그인하지 않은 사람이 프로필 표에 접근할 수 있음';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.join_group(current_setting('test.code'));
    assert false, '시험 실패: 로그인하지 않은 사람이 모임에 가입할 수 있음';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 7. 만료된 초대 코드로는 들어올 수 없다
-- ---------------------------------------------------------------------
update public.invites set expires_at = now() - interval '1 day' where code = current_setting('test.code');

select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.invite_preview(current_setting('test.code'))) = 0,
    '시험 실패: 만료된 초대 코드로 모임 정보가 보임';
  begin
    perform public.join_group(current_setting('test.code'));
    assert false, '시험 실패: 만료된 초대 코드로 가입할 수 있음';
  exception when raise_exception then null;
  end;
end $$;

reset role;

-- ---------------------------------------------------------------------
-- 8. 영희가 모임을 나가면, 영희가 모임에 공개했던 글은 "나만 보기"가 된다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000002", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  perform public.leave_group(current_setting('test.gid')::uuid);
  assert (select group_id from public.prayers where id = current_setting('test.pid')::uuid) is null,
    '시험 실패: 나간 모임에 공개했던 글이 나만 보기로 바뀌어야 함';
  assert (select count(*) from public.groups) = 0, '시험 실패: 나간 모임이 계속 보임';
end $$;

reset role;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.prayers) = 0, '시험 실패: 나간 멤버의 글이 남은 멤버에게 보임';
  assert (select count(*) from public.profiles where id = '00000000-0000-4000-8000-000000000002') = 0,
    '시험 실패: 더 이상 같은 모임이 아닌 사람의 프로필이 보임';
end $$;

select set_config('test.code2', public.create_invite(current_setting('test.gid')::uuid), true);

reset role;

-- ---------------------------------------------------------------------
-- 9. 미미(모임장)가 탈퇴하면: 철수가 새 모임장이 되고, 미미의 기록은 모두 지워진다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;
select public.join_group(current_setting('test.code2'));
reset role;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
set local role authenticated;
select public.delete_account();
reset role;

do $$
declare gid uuid := current_setting('test.gid')::uuid;
begin
  assert not exists (select 1 from auth.users where id = '00000000-0000-4000-8000-000000000001'),
    '시험 실패: 탈퇴한 계정이 남아 있음';
  assert not exists (select 1 from public.profiles where id = '00000000-0000-4000-8000-000000000001'),
    '시험 실패: 탈퇴한 사람의 프로필이 남아 있음';
  assert not exists (select 1 from public.reactions where user_id = '00000000-0000-4000-8000-000000000001'),
    '시험 실패: 탈퇴한 사람의 반응이 남아 있음';
  assert (select role from public.group_members where group_id = gid and user_id = '00000000-0000-4000-8000-000000000003') = 'leader',
    '시험 실패: 모임장이 탈퇴하면 남은 멤버가 모임장이 되어야 함';
end $$;

-- ---------------------------------------------------------------------
-- 10. 마지막 멤버(철수)가 나가면 모임이 삭제된다
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-000000000003", "role": "authenticated"}', true);
set local role authenticated;
select public.leave_group(current_setting('test.gid')::uuid);
reset role;

do $$ begin
  assert not exists (select 1 from public.groups where id = current_setting('test.gid')::uuid),
    '시험 실패: 마지막 멤버가 나가면 모임이 삭제되어야 함';
end $$;

-- 시험으로 만든 데이터를 모두 되돌린다
rollback;

select '모든 보안 시험 통과' as 결과;
