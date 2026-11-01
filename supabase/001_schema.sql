-- =====================================================================
-- 윗블 데이터베이스 설계 v1
--
-- 실행 방법: Supabase 대시보드 > SQL Editor > New query 에 이 파일 전체를
--           붙여넣고 Run. **처음 한 번만** 실행한다.
--           (나중에 바꿀 내용은 002_..., 003_... 새 파일로 만든다)
--
-- 보안 원칙
--   1. 모든 표에 RLS(행 단위 보안 규칙)를 켠다. 규칙이 없으면 아무도 못 본다.
--   2. 로그인하지 않은 사람(anon)은 어떤 표에도 접근할 수 없다.
--   3. 모임 만들기·초대·가입·나가기·탈퇴처럼 여러 표를 함께 바꾸는 일은
--      아래 함수(RPC)로만 할 수 있다. 함수 안에서 권한을 다시 확인한다.
--   4. 규칙에 쓰는 도우미 함수는 private 스키마에 둬서 앱에서 직접 부를 수 없다.
-- =====================================================================

begin;

create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------
-- 1. 표 만들기
-- ---------------------------------------------------------------------

-- 프로필: 같은 모임 멤버에게 보이는 정보
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 12),
  bio         text not null default '' check (char_length(bio) <= 30),
  avatar_url  text check (avatar_url is null or avatar_url like 'https://%'),
  created_at  timestamptz not null default now()
);

-- 내 설정과 마지막 읽은 위치: 나만 보는 정보
create table public.user_settings (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  notify         boolean not null default true,
  def_vis        text not null default 'private',        -- 'private' 또는 모임 id
  last_book      smallint check (last_book between 0 and 65),
  last_chapter   smallint check (last_chapter between 1 and 150),
  last_progress  smallint not null default 0 check (last_progress between 0 and 100)
);

-- 가입 동의 기록: 언제, 어느 버전에, 무엇에 동의했는지 (수정·삭제 불가)
create table public.consents (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  item        text not null check (item in ('age14', 'collect', 'sensitive', 'overseas', 'photo')),
  version     text not null check (char_length(version) between 1 and 10),
  agreed      boolean not null,
  created_at  timestamptz not null default now()
);
create index on public.consents (user_id);

-- 모임
create table public.groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 1 and 20),
  type         text not null default '셀/목장'
               check (type in ('셀/목장', '교회 부서', '성경 읽기 모임', '가족', '기타')),
  description  text not null default '' check (char_length(description) <= 200),
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

-- 모임 멤버 (leader = 모임장)
create table public.group_members (
  group_id   uuid not null references public.groups(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'member' check (role in ('leader', 'member')),
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index on public.group_members (user_id);

-- 초대 코드 (예: X7K2Q9MD). 14일 뒤 만료
create table public.invites (
  code        text primary key check (code ~ '^[A-Z0-9]{8}$'),
  group_id    uuid not null references public.groups(id) on delete cascade,
  created_by  uuid references auth.users(id) on delete set null,
  expires_at  timestamptz not null default now() + interval '14 days',
  created_at  timestamptz not null default now()
);
create index on public.invites (group_id);

-- 묵상. group_id가 비어 있으면 "나만 보기"
create table public.meditations (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  group_id     uuid references public.groups(id) on delete set null,
  ref_book     smallint check (ref_book between 0 and 65),
  ref_chapter  smallint check (ref_chapter between 1 and 150),
  ref_verses   smallint[] check (ref_verses is null or cardinality(ref_verses) between 1 and 176),
  body         text not null check (char_length(body) between 1 and 3000),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check ((ref_book is null) = (ref_chapter is null))
);
create index on public.meditations (group_id, created_at desc);
create index on public.meditations (author_id, created_at desc);

-- 기도제목. group_id가 비어 있으면 "나만 보기"
create table public.prayers (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  group_id     uuid references public.groups(id) on delete set null,
  ref_book     smallint check (ref_book between 0 and 65),
  ref_chapter  smallint check (ref_chapter between 1 and 150),
  ref_verses   smallint[] check (ref_verses is null or cardinality(ref_verses) between 1 and 176),
  title        text not null check (char_length(title) between 1 and 40),
  body         text not null default '' check (char_length(body) <= 3000),
  status       text not null default 'praying' check (status in ('praying', 'answered')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check ((ref_book is null) = (ref_chapter is null))
);
create index on public.prayers (group_id, created_at desc);
create index on public.prayers (author_id, created_at desc);

-- 반응 ("공감", "함께 기도"). 묵상 또는 기도제목 중 하나에만 붙는다
create table public.reactions (
  id             bigint generated always as identity primary key,
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  meditation_id  uuid references public.meditations(id) on delete cascade,
  prayer_id      uuid references public.prayers(id) on delete cascade,
  created_at     timestamptz not null default now(),
  check (num_nonnulls(meditation_id, prayer_id) = 1),
  unique (user_id, meditation_id),
  unique (user_id, prayer_id)
);
create index on public.reactions (meditation_id);
create index on public.reactions (prayer_id);

-- 하이라이트, 저장한 말씀, 성경 읽은 날: 나만 보는 정보
create table public.highlights (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  book        smallint not null check (book between 0 and 65),
  chapter     smallint not null check (chapter between 1 and 150),
  verse       smallint not null check (verse between 1 and 176),
  created_at  timestamptz not null default now(),
  primary key (user_id, book, chapter, verse)
);

create table public.saved_verses (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  book        smallint not null check (book between 0 and 65),
  chapter     smallint not null check (chapter between 1 and 150),
  verse       smallint not null check (verse between 1 and 176),
  created_at  timestamptz not null default now(),
  primary key (user_id, book, chapter, verse)
);

create table public.reading_days (
  user_id  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day      date not null,
  primary key (user_id, day)
);

-- ---------------------------------------------------------------------
-- 2. 보안 규칙에 쓰는 도우미 함수 (앱에서 직접 부를 수 없음)
-- ---------------------------------------------------------------------

-- 내가 이 모임의 멤버인가?
create function private.is_member(gid uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and user_id = (select auth.uid())
  );
$$;

-- 내가 이 모임의 모임장인가?
create function private.is_leader(gid uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and user_id = (select auth.uid()) and role = 'leader'
  );
$$;

-- 이 사람과 나는 같은 모임에 속해 있나?
create function private.shares_group(other uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members a
    join public.group_members b on a.group_id = b.group_id
    where a.user_id = (select auth.uid()) and b.user_id = other
  );
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- ---------------------------------------------------------------------
-- 3. 보안 규칙 (RLS)
-- ---------------------------------------------------------------------

alter table public.profiles       enable row level security;
alter table public.user_settings  enable row level security;
alter table public.consents       enable row level security;
alter table public.groups         enable row level security;
alter table public.group_members  enable row level security;
alter table public.invites        enable row level security;
alter table public.meditations    enable row level security;
alter table public.prayers        enable row level security;
alter table public.reactions      enable row level security;
alter table public.highlights     enable row level security;
alter table public.saved_verses   enable row level security;
alter table public.reading_days   enable row level security;

-- 프로필: 나 자신과 같은 모임 멤버만 볼 수 있다. 수정은 본인만.
create policy "프로필 보기" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.shares_group(id));
create policy "프로필 수정" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- 나만 보는 표: 본인 것만 읽고 쓰고 지울 수 있다.
create policy "내 설정" on public.user_settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "내 하이라이트" on public.highlights for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "내 저장 말씀" on public.saved_verses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "내 읽은 날" on public.reading_days for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- 동의 기록: 본인 것만 보고 추가할 수 있다. 수정·삭제 규칙은 없다(=불가).
create policy "내 동의 보기" on public.consents for select to authenticated
  using (user_id = (select auth.uid()));
create policy "내 동의 추가" on public.consents for insert to authenticated
  with check (user_id = (select auth.uid()));

-- 모임: 멤버만 볼 수 있다. 이름·설명 수정과 모임 삭제는 모임장만.
--       (모임 만들기는 create_group 함수로만)
create policy "모임 보기" on public.groups for select to authenticated
  using (private.is_member(id));
create policy "모임 수정" on public.groups for update to authenticated
  using (private.is_leader(id)) with check (private.is_leader(id));
create policy "모임 삭제" on public.groups for delete to authenticated
  using (private.is_leader(id));

-- 모임 멤버: 같은 모임 멤버만 명단을 볼 수 있다.
--            모임장은 다른 멤버를 내보낼 수 있다. (가입·나가기는 함수로만)
create policy "멤버 보기" on public.group_members for select to authenticated
  using (private.is_member(group_id));
create policy "멤버 내보내기" on public.group_members for delete to authenticated
  using (private.is_leader(group_id) and user_id <> (select auth.uid()));

-- 초대 코드: 그 모임 멤버만 볼 수 있다. 모임장은 코드를 지울(취소할) 수 있다.
--            (만들기는 create_invite 함수로만)
create policy "초대 보기" on public.invites for select to authenticated
  using (private.is_member(group_id));
create policy "초대 취소" on public.invites for delete to authenticated
  using (private.is_leader(group_id));

-- 묵상: 작성자 본인 + (모임에 공개했다면) 그 모임 멤버만 볼 수 있다.
--       쓰기·수정은 본인만, 공개할 모임은 내가 속한 모임만.
--       삭제는 본인 또는 그 모임의 모임장(부적절한 글 정리용).
create policy "묵상 보기" on public.meditations for select to authenticated
  using (author_id = (select auth.uid()) or (group_id is not null and private.is_member(group_id)));
create policy "묵상 쓰기" on public.meditations for insert to authenticated
  with check (author_id = (select auth.uid()) and (group_id is null or private.is_member(group_id)));
create policy "묵상 수정" on public.meditations for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()) and (group_id is null or private.is_member(group_id)));
create policy "묵상 삭제" on public.meditations for delete to authenticated
  using (author_id = (select auth.uid()) or (group_id is not null and private.is_leader(group_id)));

-- 기도제목: 묵상과 같은 규칙
create policy "기도 보기" on public.prayers for select to authenticated
  using (author_id = (select auth.uid()) or (group_id is not null and private.is_member(group_id)));
create policy "기도 쓰기" on public.prayers for insert to authenticated
  with check (author_id = (select auth.uid()) and (group_id is null or private.is_member(group_id)));
create policy "기도 수정" on public.prayers for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()) and (group_id is null or private.is_member(group_id)));
create policy "기도 삭제" on public.prayers for delete to authenticated
  using (author_id = (select auth.uid()) or (group_id is not null and private.is_leader(group_id)));

-- 반응: 내가 볼 수 있는 글에 달린 반응만 보이고, 그런 글에만 반응할 수 있다.
--       (아래 exists 안의 묵상·기도 조회에도 위 규칙이 그대로 적용된다)
create policy "반응 보기" on public.reactions for select to authenticated
  using (
    exists (select 1 from public.meditations m where m.id = meditation_id)
    or exists (select 1 from public.prayers p where p.id = prayer_id)
  );
create policy "반응 남기기" on public.reactions for insert to authenticated
  with check (
    user_id = (select auth.uid()) and (
      exists (select 1 from public.meditations m where m.id = meditation_id)
      or exists (select 1 from public.prayers p where p.id = prayer_id)
    )
  );
create policy "반응 취소" on public.reactions for delete to authenticated
  using (user_id = (select auth.uid()));

-- 로그인하지 않은 사람은 어떤 표에도 접근할 수 없다.
revoke all on all tables in schema public from anon;

-- ---------------------------------------------------------------------
-- 4. 자동 처리 (트리거)
-- ---------------------------------------------------------------------

-- 카카오로 처음 로그인하면 프로필과 설정을 자동으로 만든다.
-- 이름은 카카오 닉네임(12자까지), 사진은 카카오가 보내준 경우에만 저장.
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  nick text := left(btrim(coalesce(meta->>'name', meta->>'nickname', meta->>'full_name', meta->>'user_name', '')), 12);
  pic  text := coalesce(meta->>'avatar_url', meta->>'picture');
begin
  insert into public.profiles (id, name, avatar_url)
  values (new.id,
          case when nick = '' then '윗블 친구' else nick end,
          case when pic like 'https://%' then pic end);
  insert into public.user_settings (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- 묵상·기도를 고치면 수정 시각을 자동으로 기록한다.
create function private.touch_updated_at() returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  new.created_at := old.created_at;   -- 작성 시각은 바꿀 수 없음
  return new;
end;
$$;

create trigger meditations_touch before update on public.meditations
  for each row execute function private.touch_updated_at();
create trigger prayers_touch before update on public.prayers
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------
-- 5. 앱에서 부르는 함수 (RPC)
-- ---------------------------------------------------------------------

-- 모임 만들기: 모임을 만들고 나를 모임장으로 등록한다. 새 모임 id를 돌려준다.
create function public.create_group(p_name text, p_type text default '셀/목장', p_description text default '')
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  gid uuid;
begin
  if uid is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  if (select count(*) from public.group_members where user_id = uid and role = 'leader') >= 20 then
    raise exception '모임은 20개까지 만들 수 있어요';
  end if;
  insert into public.groups (name, type, description, created_by)
  values (btrim(p_name), p_type, btrim(coalesce(p_description, '')), uid)
  returning id into gid;
  insert into public.group_members (group_id, user_id, role) values (gid, uid, 'leader');
  return gid;
end;
$$;

-- 초대 코드 만들기: 모임 멤버면 누구나 만들 수 있다. 8자리 코드를 돌려준다.
-- 헷갈리는 글자(0, O, 1, I)를 뺀 32글자 중에서 무작위로 고른다.
create function public.create_invite(p_group uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  idx constant int[] := array[0, 1, 2, 3, 4, 5, 10, 11];  -- uuid에서 무작위인 바이트 위치
  b bytea;
  c text;
  i int;
begin
  if not private.is_member(p_group) then raise exception '모임 멤버만 초대할 수 있어요' using errcode = '42501'; end if;
  loop
    b := uuid_send(gen_random_uuid());
    c := '';
    foreach i in array idx loop
      c := c || substr(alphabet, get_byte(b, i) % 32 + 1, 1);
    end loop;
    begin
      insert into public.invites (code, group_id, created_by) values (c, p_group, auth.uid());
      return c;
    exception when unique_violation then
      -- 아주 드물게 같은 코드가 나오면 다시 만든다
    end;
  end loop;
end;
$$;

-- 초대 미리보기: 초대 링크를 연 사람에게 "OO 모임에 초대받았어요"를 보여줄 정보.
-- 유효한 코드일 때만 모임 이름·종류·인원수를 돌려준다.
create function public.invite_preview(p_code text)
returns table (group_id uuid, name text, type text, member_count bigint, already_member boolean)
language sql stable security definer set search_path = ''
as $$
  select g.id, g.name, g.type,
         (select count(*) from public.group_members m where m.group_id = g.id),
         private.is_member(g.id)
  from public.invites i
  join public.groups g on g.id = i.group_id
  where i.code = upper(btrim(p_code)) and i.expires_at > now() and auth.uid() is not null;
$$;

-- 초대 수락: 유효한 코드면 모임 멤버로 등록하고 모임 id를 돌려준다.
create function public.join_group(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  gid uuid;
begin
  if uid is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  select i.group_id into gid from public.invites i
  where i.code = upper(btrim(p_code)) and i.expires_at > now();
  if gid is null then raise exception '초대 링크가 만료되었거나 올바르지 않아요'; end if;
  if (select count(*) from public.group_members where group_id = gid) >= 200 then
    raise exception '모임 인원이 가득 찼어요 (최대 200명)';
  end if;
  insert into public.group_members (group_id, user_id) values (gid, uid)
  on conflict do nothing;
  return gid;
end;
$$;

-- 모임 나가기
--  - 내가 이 모임에 공개한 묵상·기도는 "나만 보기"로 바뀐다 (남은 멤버에게 안 보임)
--  - 모임장이 나가면 가장 먼저 들어온 멤버가 새 모임장이 된다
--  - 마지막 멤버가 나가면 모임이 삭제된다
create function public.leave_group(p_group uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  was_leader boolean;
  next_leader uuid;
begin
  select role = 'leader' into was_leader from public.group_members
  where group_id = p_group and user_id = uid;
  if was_leader is null then raise exception '이 모임의 멤버가 아니에요'; end if;

  update public.meditations set group_id = null where author_id = uid and group_id = p_group;
  update public.prayers     set group_id = null where author_id = uid and group_id = p_group;
  delete from public.group_members where group_id = p_group and user_id = uid;

  if was_leader then
    select user_id into next_leader from public.group_members
    where group_id = p_group order by joined_at, user_id limit 1;
    if next_leader is null then
      delete from public.groups where id = p_group;
    elsif not exists (select 1 from public.group_members where group_id = p_group and role = 'leader') then
      update public.group_members set role = 'leader' where group_id = p_group and user_id = next_leader;
    end if;
  end if;
end;
$$;

-- 회원 탈퇴: 모든 모임에서 나간 뒤 계정과 모든 기록을 삭제한다.
-- (프로필·묵상·기도·반응·하이라이트·동의 기록 등은 계정 삭제 시 함께 지워진다)
create function public.delete_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  gid uuid;
begin
  if uid is null then raise exception '로그인이 필요해요' using errcode = '42501'; end if;
  for gid in select group_id from public.group_members where user_id = uid loop
    perform public.leave_group(gid);
  end loop;
  delete from auth.users where id = uid;
end;
$$;

-- 함수는 로그인한 사람만 부를 수 있다.
revoke all on function public.create_group(text, text, text) from public, anon;
revoke all on function public.create_invite(uuid)           from public, anon;
revoke all on function public.invite_preview(text)          from public, anon;
revoke all on function public.join_group(text)              from public, anon;
revoke all on function public.leave_group(uuid)             from public, anon;
revoke all on function public.delete_account()              from public, anon;
grant execute on function public.create_group(text, text, text) to authenticated;
grant execute on function public.create_invite(uuid)           to authenticated;
grant execute on function public.invite_preview(text)          to authenticated;
grant execute on function public.join_group(text)              to authenticated;
grant execute on function public.leave_group(uuid)             to authenticated;
grant execute on function public.delete_account()              to authenticated;

-- 트리거용 함수는 아무도 직접 부를 수 없다.
revoke all on function private.handle_new_user()  from public, anon, authenticated;
revoke all on function private.touch_updated_at() from public, anon, authenticated;

commit;
