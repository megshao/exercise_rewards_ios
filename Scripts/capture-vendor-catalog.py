#!/usr/bin/env python3
"""把 500.gov.tw 的廠商品項頁（/intro/vendor-N.html）解析成 vendor-catalog.json。

兩種版型都要處理：
  - details 版（vendor-1/2/3）：<details data-category="X"> 內含 <li data-name="...">，
    是**完整清單**；分類上還可能有 <h3 class="product-subtitle"> 把清單分成幾組
    （vendor-3 有兩組，且兩組的分類名稱會重複，所以分類必須掛在組底下）。
  - table 版（vendor-5/7）：<tr><td>分類</td><td>舉例</td></tr>，官網給的是**舉例**
    （v5 每列以「等」結尾、v7 用「/」分隔），不是完整清單。

完整性校驗：details 版每個分類的 <span class="item-count">N 項</span> 必須等於實際
解析到的 <li> 數量，不符就報錯——這是這份快照能不能被信任的唯一機械檢查。

重跑方式（官網改版後重新產生快照）：
    python3 parse_intro.py <intro-html-dir> <offers.json> > vendor-catalog.json
"""
import html
import json
import re
import sys
from pathlib import Path

VENDORS = [1, 2, 3, 5, 7]


def text(raw: str) -> str:
    """去標籤、還原 entity、收斂空白。品項名裡有全形空白，只 strip 兩端。"""
    return html.unescape(re.sub(r"<[^>]+>", "", raw)).strip()


def parse_details(page: str):
    """回傳 (groups, 校驗錯誤清單)。groups = [{title, categories:[{name, items, statedCount}]}]

    **刻意排除「全部品項」那張彙總卡**（它不是 category-card）：內容是各分類的聯集，
    而且官網自己那個計數沒有去重（7-11 標 473，去重後 442）。備份保留分類結構，
    要看全部由 App 自己聯集，不必存兩份同樣的資料。
    """
    problems = []
    # 先按 product-subtitle 切段；沒有 subtitle 就整頁一段（title=None）。
    subtitle_re = re.compile(r'<h3 class="product-subtitle">(.*?)</h3>', re.S)
    marks = [(m.start(), text(m.group(1))) for m in subtitle_re.finditer(page)]
    if marks:
        spans = []
        for i, (pos, title) in enumerate(marks):
            end = marks[i + 1][0] if i + 1 < len(marks) else len(page)
            spans.append((title, page[pos:end]))
    else:
        spans = [(None, page)]

    detail_re = re.compile(
        r'<details class="category-card" data-category="(?P<cat>[^"]*)".*?</details>', re.S)
    count_re = re.compile(r'<span class="item-count">\s*(\d+)\s*項')
    li_re = re.compile(r'<li data-name="(?P<name>[^"]*)"')

    groups = []
    for title, chunk in spans:
        categories = []
        for d in detail_re.finditer(chunk):
            block = d.group(0)
            name = html.unescape(d.group("cat"))
            items = [html.unescape(m.group("name")).strip() for m in li_re.finditer(block)]
            declared = count_re.search(block)
            if declared and int(declared.group(1)) != len(items):
                problems.append(
                    f"{name}: 頁面聲明 {declared.group(1)} 項，實際解析 {len(items)} 項")
            if not items:
                problems.append(f"{name}: 解析到 0 項")
            entry = {"name": name, "items": items}
            if declared:
                # 官網自標的數量。以它為準、不用 items.count 取代——兩者不一致就是
                # 解析漏了東西的訊號（見 VendorIntroCategory.statedCount）。
                entry["statedCount"] = int(declared.group(1))
            categories.append(entry)
        if categories:
            groups.append({"title": title, "categories": categories})
    return groups, problems


def parse_table(page: str):
    """表格版：官網給的是舉例字串，原封保留、不自行切開。"""
    problems = []
    tbody = re.search(r"<tbody>(.*?)</tbody>", page, re.S)
    body = tbody.group(1) if tbody else page
    rows = []
    for tr in re.findall(r"<tr>(.*?)</tr>", body, re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)
        if len(cells) < 2:
            continue  # 表頭是 <th>，會自然被跳過
        rows.append({"name": text(cells[0]), "examples": text(cells[1])})
    if not rows:
        problems.append("表格版解析到 0 列")
    return [{"title": None, "categories": rows}], problems


def main() -> int:
    src_dir = Path(sys.argv[1])
    offers = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    by_path = {v["introPath"]: v for v in offers["vendors"]}

    all_problems = []
    for n in VENDORS:
        page = (src_dir / f"vendor-{n}.html").read_text(encoding="utf-8")
        path = f"/intro/vendor-{n}.html"
        vendor = by_path.get(path)
        if vendor is None:
            all_problems.append(f"{path}: 兌換頁沒有這家廠商，無法對應")
            continue

        is_details = 'class="category-card"' in page
        groups, problems = parse_details(page) if is_details else parse_table(page)
        all_problems += [f"vendor-{n} {p}" for p in problems]

        h1 = re.search(r"<h1>(.*?)</h1>", page, re.S)
        notice = re.search(r'<aside class="notice">.*?<p>(.*?)</p>', page, re.S)

        vendor["catalog"] = {
            # 「full」＝官網逐項列出；「examples」＝官網只給舉例（結尾有「等」或以「/」分隔），
            # 顯示時必須講清楚不是完整清單。
            "listing": "full" if is_details else "examples",
            "introTitle": text(h1.group(1)) if h1 else None,
            "notice": text(notice.group(1)) if notice else None,
            "groups": groups,
        }

    total = sum(
        len(c.get("items", []) or [1])
        for v in offers["vendors"] for g in v.get("catalog", {}).get("groups", [])
        for c in g["categories"]
    )
    print(json.dumps(offers, ensure_ascii=False, indent=2))
    for p in all_problems:
        print(f"PROBLEM: {p}", file=sys.stderr)
    print(f"parsed rows/items total={total}", file=sys.stderr)
    return 1 if all_problems else 0


if __name__ == "__main__":
    sys.exit(main())
