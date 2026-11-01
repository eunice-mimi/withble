# 윗블 (Withble)

With + Bible. 성경을 읽고, 묵상과 기도제목을 모임(셀·부서·가족)과 나누는 모바일 성경·공동체 앱.
지금은 MVP 기획서를 바탕으로 만든 **클릭 가능한 모바일 웹 프로토타입** 단계이다.

## 작업 방식 (중요)

- 나는 앱 개발이 처음이다. 바꾼 내용은 쉬운 한국어로 짧게 설명해 줘.
- 수정할 때는 **어떤 파일의 몇 번째 줄 근처가 왜 바뀌었는지** 알려줘.
- 설명은 간결하게. 한 번에 크게 바꾸지 말고 작은 단계로 나눠서 진행해 줘.
- 파일 구조를 바꾸거나 많은 코드를 지우는 큰 작업은 시작 전에 계획을 먼저 보여주고 확인받아.
- 작업 단위가 끝나면 git 커밋을 해 줘 (git이 없으면 `git init`부터).

## 현재 구조

- `index.html` 한 파일에 HTML·CSS·JS가 모두 들어 있음 (약 1MB).
  - 대부분은 base64로 내장된 Pretendard 폰트(`@font-face`)이고, 실제 코드는 약 90KB.
  - 본문용 명조체 Gowun Batang은 Google Fonts에서 불러옴.
- 화면은 `SC` 객체에 함수로 정의됨:
  login, home, notifs, books, chapters, reader, search, medEdit, prayEdit,
  medDetail, prayDetail, shareVerse, records, groups, groupNew, groupCreated, group, my
- 화면 이동: `UI.stack` 기반 (`go`, `back`, `replace`, `tab` 함수), 하단 탭 5개(home·bible·groups·records·my).
- 데이터 저장: `localStorage` 키 `withble.prototype.v1`. 처음 실행 시 `seed()`가 더미 데이터 생성.
- 성경 목록: `OT`, `NT` 배열 → `BOOKS` (각 항목 `{name, ch, t:'ot'|'nt'}`).

## 성경 본문 (다음 작업)

- 현재 `TEXT` 객체에 샘플 4장만 하드코딩되어 있음: 시편 23편, 요한복음 3·15장, 마태복음 5장.
  - 키 형식: `TEXT['책인덱스-장']` = `{ v: ['1절', '2절', ...] }`
  - `AVAILABLE`, `TODAY_REF`, `PRESETS`가 이 샘플 장에 의존함.
- **목표: 개역한글 전체(66권 1,189장 31,102절)로 교체.**
- 데이터 출처: GitHub `yuhwan/Bible-krv` (https://github.com/yuhwan/Bible-krv)
  - 책별 JSON 66개 + `books.json`(책 순서 목록).
  - 형식: `{"book":"요한복음","chapters":[{"chapter":1,"verses":[{"verse":1,"text":"..."}]}]}`
  - 개역한글(1961)은 저작권이 만료된 퍼블릭 도메인. **개역개정은 저작권이 있으므로 쓰지 말 것.**
- 주의할 점:
  - 책 이름 불일치: 앱은 `요한일서/요한이서/요한삼서`, 데이터는 `요한1서/요한2서/요한3서`. 매칭할 때 처리 필요.
  - 시편 일부는 1절 앞에 `[다윗의 시]` 같은 표제가 붙어 있음 → 본문과 분리해서 작은 회색 글씨로 표시.
  - 별도 JSON 파일을 `fetch`로 읽으면 파일을 더블클릭(file://)해서는 안 열림. 로컬 서버로 실행할 것
    (예: `python3 -m http.server` 또는 `npx serve`). 실행 방법도 알려줘.
  - 검색(`searchResults`)이 `TEXT` 전체를 순회하므로, 전체 본문이 들어가면 속도를 확인할 것.

## 디자인 시스템

- 컨셉: 현대카드 스타일. **컬러 없이 블랙 메인** (예외: 카카오 공유 버튼의 노란색만).
- 서체: UI는 Pretendard, 성경 본문은 명조(Gowun Batang).
- 라운드 기본값 4px (`--radius-base`).
- 색·여백·크기는 `:root`의 CSS 변수(토큰)만 사용하고 값을 직접 쓰지 말 것:
  - 색: `--ink`, `--surface`, `--surface-sunken`, `--muted`, `--line`, `--hl` 등 (다크 모드 값 정의됨)
  - 여백: `--space-1`(4px) ~ `--space-16`(64px), 화면 좌우 여백 `--margin-screen`(24px)
  - 컨트롤 높이: `--control-lg`(56) / `--control-md`(48) / `--control-sm`(40), 최소 터치 영역 44px
- 새 화면·컴포넌트도 기존 화면과 같은 패턴(`hdr`, `.btn`, `.chip`, `.post` 등)을 재사용할 것.

## 참고 문서

- MVP 기획서: `docs/` 폴더에 넣어둘 예정. 있으면 기능 판단 시 먼저 참고할 것.
