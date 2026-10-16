#!/usr/bin/env python3
"""개역한글 원본(yuhwan/Bible-krv)의 책별 JSON 66개를 앱용 data/krv.json 한 파일로 합친다.

사용법:
  1) https://github.com/yuhwan/Bible-krv 를 내려받아 JSON 파일들이 있는 폴더를 준비
  2) python3 tools/build-krv.py <JSON 폴더 경로>

결과 형식 (data/krv.json):
  {
    "books":  [ [ ["1절", "2절", ...], ...각 장 ], ...66권 (앱의 BOOKS 순서) ],
    "titles": { "책인덱스-장": "시편 표제", ... }
  }
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'krv.json')
APP = os.path.join(ROOT, 'index.html')

# 데이터와 앱의 책 이름이 다른 경우 (데이터 이름 -> 앱 이름)
RENAME = {'요한1서': '요한일서', '요한2서': '요한이서', '요한3서': '요한삼서'}

# 시편 1절 앞의 표제: "[다윗의 시] 본문..."
TITLE = re.compile(r'^\[([^\]]+)\]\s*')


def app_books():
    """index.html의 OT/NT 배열에서 [책 이름, 장 수] 목록을 읽는다."""
    src = open(APP, encoding='utf-8').read()
    books = []
    for name in ('OT', 'NT'):
        line = re.search(r'^const ' + name + r'=\[(.*)\];$', src, re.M).group(1)
        books += [(n, int(c)) for n, c in re.findall(r"\['([^']+)',(\d+)\]", line)]
    return books


def main(src_dir):
    books = app_books()
    data = {}
    for f in os.listdir(src_dir):
        if f.endswith('.json') and f != 'books.json':
            b = json.load(open(os.path.join(src_dir, f), encoding='utf-8'))
            data[RENAME.get(b['book'], b['book'])] = b

    out_books, titles, n_ch, n_v = [], {}, 0, 0
    for i, (name, ch_count) in enumerate(books):
        b = data.get(name)
        assert b, '데이터에 없는 책: ' + name
        chapters = sorted(b['chapters'], key=lambda c: c['chapter'])
        assert len(chapters) == ch_count, f'{name} 장 수 불일치: {len(chapters)} != {ch_count}'
        out_ch = []
        for c in chapters:
            verses = sorted(c['verses'], key=lambda v: v['verse'])
            assert [v['verse'] for v in verses] == list(range(1, len(verses) + 1)), f'{name} {c["chapter"]}장 절 번호 이상'
            texts = [v['text'].strip() for v in verses]
            if name == '시편':
                m = TITLE.match(texts[0])
                if m:
                    titles[f'{i}-{c["chapter"]}'] = m.group(1).strip()
                    texts[0] = texts[0][m.end():]
            out_ch.append(texts)
            n_v += len(texts)
        out_books.append(out_ch)
        n_ch += len(out_ch)

    assert (len(out_books), n_ch, n_v) == (66, 1189, 31102), (len(out_books), n_ch, n_v)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as fp:
        json.dump({'books': out_books, 'titles': titles}, fp, ensure_ascii=False, separators=(',', ':'))
    print(f'{len(out_books)}권 {n_ch}장 {n_v}절, 시편 표제 {len(titles)}개 -> {OUT} ({os.path.getsize(OUT) // 1024}KB)')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
