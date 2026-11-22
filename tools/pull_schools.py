#!/usr/bin/env python3
"""
学校库全量拉取与转换脚本（开发期手动工具，不进 CI / App / 打包）。

数据来源：
  仓库：https://github.com/qiqqqqq517/shangkeschedule
  协议：Apache-2.0
  文件：shared/assets/offline_repo/schools/timetable_schools.json

仅拉取学校基础元数据（校名、教务网址、系统类型），不引入任何教务适配脚本。
"""

from __future__ import annotations

import ipaddress
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

try:
    from pypinyin import Style, lazy_pinyin
except ImportError as exc:
    sys.stderr.write(
        "错误：缺少依赖 pypinyin。\n"
        "请先在开发虚拟环境中安装：\n"
        "  ~/workspace/.venv-pw/bin/pip install pypinyin\n"
    )
    raise SystemExit(1) from exc

UPSTREAM_URL = (
    "https://raw.githubusercontent.com/qiqqqqq517/shangkeschedule/"
    "main/shared/assets/offline_repo/schools/timetable_schools.json"
)

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "assets" / "data" / "schools.json"

SYSTEM_MAP: dict[str, str] = {
    "zhengfang_new": "正方教务",
    "qiangzhi": "强智教务",
    "qiangzhi_old": "强智教务",
    "kingosoft_new": "青果教务",
    "kingosoft": "青果教务",
    "wisedu": "金智教务",
    "chaoxing": "超星教务",
    "urp": "URP教务",
    "urp_new": "URP教务",
    "south_soft": "南软教务",
}

CONFIRM_TYPES = {"allogene", "dlut"}
TOKEN_QUERY_KEYS = {"token", "sessionid", "jsessionid", "ticket"}

ZJNU_OLD_URL = "http://jwgl.zjnu.edu.cn/"
ZJNU_NEW_URL = "https://jwxt.zjnu.edu.cn/"
DLOU_OLD_URL = "https://portal.dlou.edu.cn/auth/cas/login?service=https%3A%2F%2Fjwxt.dlou.edu.cn%2Fsso%2Fddlogin"
DLOU_NEW_URL = "https://jwxt.dlou.edu.cn/"


def fetch_upstream_json(url: str) -> list[dict[str, Any]]:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "xiaoma-timetable-pull-schools/1.0"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError("上游 JSON 顶层不是数组")
    return data


def is_private_host(host: str) -> bool:
    host_lower = host.lower().strip("[]")
    if host_lower == "localhost":
        return True
    try:
        ip = ipaddress.ip_address(host_lower)
    except ValueError:
        return False
    if ip.version == 4:
        octets = host_lower.split(".")
        if len(octets) == 4:
            first, second = int(octets[0]), int(octets[1])
            if first in (10, 127):
                return True
            if first == 192 and second == 168:
                return True
            if first == 172 and 16 <= second <= 31:
                return True
    return False


def classify_url(url: str) -> str:
    """
    返回:
      "ok"      - 合法保留
      "invalid" - 畸形或内网地址
      "token"   - query 含一次性会话/票据参数
    """
    if not isinstance(url, str):
        return "invalid"
    trimmed = url.strip()
    if not trimmed:
        return "invalid"

    try:
        parsed = urllib.parse.urlsplit(trimmed)
    except ValueError:
        return "invalid"

    scheme = parsed.scheme.lower()
    if scheme not in ("http", "https"):
        return "invalid"

    host = parsed.hostname
    if not host:
        return "invalid"

    if is_private_host(host):
        return "invalid"

    if parsed.query:
        for key, _ in urllib.parse.parse_qsl(parsed.query, keep_blank_values=True):
            if key.strip().lower() in TOKEN_QUERY_KEYS:
                return "token"

    return "ok"


def compute_initial(name: str) -> str:
    stripped = name.strip()
    if not stripped:
        return "#"
    first_char = stripped[0]
    if not ("\u4e00" <= first_char <= "\u9fff"):
        return "#"
    syllables = lazy_pinyin(stripped, style=Style.NORMAL)
    if not syllables or not syllables[0]:
        return "#"
    letter = syllables[0][0].upper()
    if "A" <= letter <= "Z":
        return letter
    return "#"


def main() -> None:
    raw_items = fetch_upstream_json(UPSTREAM_URL)
    total_fetched = len(raw_items)

    # 步骤 2-4：映射、去研究生后缀、两条原位覆盖
    normalized: list[dict[str, Any]] = []
    for item in raw_items:
        if not isinstance(item, dict):
            continue
        raw_name = str(item.get("name") or "").strip()
        raw_url = str(item.get("url") or "").strip()
        raw_type = item.get("type")
        raw_type_str = str(raw_type).strip() if raw_type is not None else ""

        if raw_type_str in CONFIRM_TYPES:
            print(
                f"[需人工确认 type] type={raw_type_str!r}, "
                f"name={raw_name!r}, url={raw_url!r} -> 暂映射为 null"
            )
            system: str | None = None
        else:
            system = SYSTEM_MAP.get(raw_type_str)

        note: str | None = None
        name = raw_name
        if name.endswith(" - 研究生"):
            name = name[: -len(" - 研究生")].strip()
            note = "研究生"

        url = raw_url

        # 覆盖 1：浙师大
        if url == ZJNU_OLD_URL:
            name = "浙江师范大学"
            url = ZJNU_NEW_URL
            system = None
            note = None
        # 覆盖 2：大连海洋大学（按上游 CAS 包装地址精确匹配，保留上游 name 与 system；
        # 不按校名匹配，避免误伤同名研究生行，也避免上游改名后失效）
        elif url == DLOU_OLD_URL:
            url = DLOU_NEW_URL

        normalized.append(
            {
                "name": name,
                "system": system,
                "url": url,
                "note": note,
            }
        )

    # 步骤 5：按 url 去重，保留先出现的（放在覆盖之后）
    seen_urls: set[str] = set()
    deduped: list[dict[str, Any]] = []
    dup_dropped = 0
    for entry in normalized:
        url = entry["url"]
        if url in seen_urls:
            dup_dropped += 1
            continue
        seen_urls.add(url)
        deduped.append(entry)

    # 步骤 6-7：URL 过滤 + 计算 initial
    final_entries: list[dict[str, Any]] = []
    invalid_dropped = 0
    token_dropped = 0
    hash_initial_count = 0

    for entry in deduped:
        if not entry["name"]:
            invalid_dropped += 1
            continue
        status = classify_url(entry["url"])
        if status == "invalid":
            invalid_dropped += 1
            continue
        if status == "token":
            token_dropped += 1
            continue

        initial = compute_initial(entry["name"])
        if initial == "#":
            hash_initial_count += 1

        final_entries.append(
            {
                "name": entry["name"],
                "system": entry["system"],
                "url": entry["url"],
                "note": entry["note"],
                "initial": initial,
            }
        )

    # 步骤 8：写回 assets/data/schools.json（确定性输出）
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(final_entries, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # 步骤 9：打印统计与断言
    final_count = len(final_entries)
    az_count = final_count - hash_initial_count
    az_ratio = (az_count / final_count) if final_count > 0 else 0.0
    final_urls = {e["url"] for e in final_entries}

    print("=== 学校库转换统计 ===")
    print(f"拉取条数：{total_fetched}")
    print(f"去重丢掉数：{dup_dropped}")
    print(f"无效丢掉数：{invalid_dropped}")
    print(f"token 链接丢掉数：{token_dropped}")
    print(f'initial 为 "#" 的条数：{hash_initial_count}')
    print(f"最终条数：{final_count}（A-Z 占比：{az_ratio * 100:.2f}%）")
    print(f"输出路径：{OUTPUT_PATH}")

    assert final_count > 1500, f"最终条数不足 1500：{final_count}"
    assert az_ratio >= 0.95, f"A-Z 占比低于 95%：{az_ratio * 100:.2f}%"
    assert ZJNU_NEW_URL in final_urls, f"浙师大覆盖未生效：{ZJNU_NEW_URL}"
    assert DLOU_NEW_URL in final_urls, f"大连海洋大学覆盖未生效：{DLOU_NEW_URL}"


if __name__ == "__main__":
    main()