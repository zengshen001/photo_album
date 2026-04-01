#!/usr/bin/env python3
"""根据 img/events_mock_mannual.json，将时间与经纬度写入 img 下每张图片的 EXIF。

依赖：系统已安装 exiftool。

用法：
  python3 tools/write_exif_from_events.py
  python3 tools/write_exif_from_events.py --dry-run
  python3 tools/write_exif_from_events.py --json img/events_mock_mannual.json --img-root img
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def _iso_to_exif_datetime(iso_ts: str) -> str:
    """2025-06-01T07:30:00+08:00 -> 2025:06:01 07:30:00"""
    s = (iso_ts or "").strip()
    if not s:
        raise ValueError("empty timestamp")

    if s.endswith("Z"):
        s = s[:-1]

    # Remove timezone suffix (+08:00 / -05:00) if present.
    tz_pos = None
    for i in range(len(s) - 1, 9, -1):
        if s[i] in "+-" and i > 10:
            tz_pos = i
            break
    if tz_pos is not None:
        s = s[:tz_pos]

    if "T" not in s:
        raise ValueError(f"invalid iso timestamp: {iso_ts}")

    date_part, time_part = s.split("T", 1)
    y, m, d = date_part.split("-", 2)
    time_part = time_part.split(".", 1)[0]  # strip milliseconds if any
    hh, mm, ss = time_part.split(":", 2)
    return f"{y}:{m}:{d} {hh}:{mm}:{ss}"


def _gps_ref(value: float, pos_ref: str, neg_ref: str) -> str:
    return pos_ref if value >= 0 else neg_ref


def _load_mapping(json_path: Path) -> dict[str, tuple[str, float, float]]:
    with json_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    mapping: dict[str, tuple[str, float, float]] = {}
    for ev in data:
        for im in ev.get("images", []) or []:
            name = im.get("name")
            ex = im.get("exifInfo") or {}
            ts = ex.get("timestamp")
            lat = ex.get("latitude")
            lon = ex.get("longitude")
            if not name:
                continue
            if ts is None or lat is None or lon is None:
                continue
            mapping[name] = (str(ts), float(lat), float(lon))
    return mapping


def _write_exif(file_path: Path, iso_ts: str, lat: float, lon: float, dry_run: bool) -> None:
    exif_dt = _iso_to_exif_datetime(iso_ts)
    lat_ref = _gps_ref(lat, "N", "S")
    lon_ref = _gps_ref(lon, "E", "W")

    args = [
        "exiftool",
        "-overwrite_original",
        "-q",
        "-q",
        "-n",
        f"-DateTimeOriginal={exif_dt}",
        f"-CreateDate={exif_dt}",
        f"-ModifyDate={exif_dt}",
        f"-GPSLatitude={abs(lat)}",
        f"-GPSLatitudeRef={lat_ref}",
        f"-GPSLongitude={abs(lon)}",
        f"-GPSLongitudeRef={lon_ref}",
        str(file_path),
    ]

    if dry_run:
        print("DRY_RUN:", " ".join(args))
        return

    subprocess.run(args, check=True)


def _get_file_type(file_path: Path) -> str:
    r = subprocess.run(
        ["exiftool", "-s", "-s", "-s", "-FileType", str(file_path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return (r.stdout or "").strip()


def _convert_heic_to_jpeg_inplace(file_path: Path, dry_run: bool) -> None:
    """将 HEIC 内容转码为 JPEG，写回到同一路径（保持 .jpg 文件名不变）。"""
    tmp_out = file_path.with_name(f"{file_path.stem}.__tmp__.jpg")
    try:
        args = ["sips", "-s", "format", "jpeg", str(file_path), "--out", str(tmp_out)]
        if dry_run:
            print("DRY_RUN:", " ".join(args))
            return
        subprocess.run(args, check=True, capture_output=True)
        tmp_out.replace(file_path)
    finally:
        if tmp_out.exists():
            try:
                tmp_out.unlink()
            except Exception:
                pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", default="img/events_mock_mannual.json", help="events json 路径")
    parser.add_argument("--img-root", default="img", help="图片根目录")
    parser.add_argument("--dry-run", action="store_true", help="只打印要执行的写入命令")
    parser.add_argument(
        "--no-convert-heic",
        action="store_true",
        help="遇到 HEIC 内容但后缀是 .jpg 时，不转码，直接尝试写入（可能失败）",
    )
    args = parser.parse_args()

    json_path = Path(args.json)
    img_root = Path(args.img_root)

    if not json_path.exists():
        print(f"JSON not found: {json_path}", file=sys.stderr)
        return 2
    if not img_root.exists():
        print(f"img root not found: {img_root}", file=sys.stderr)
        return 2

    mapping = _load_mapping(json_path)
    if not mapping:
        print(f"No image exifInfo found in {json_path}", file=sys.stderr)
        return 2

    jpg_files = [p for p in img_root.rglob("*.jpg") if p.is_file()]
    jpg_files = [p for p in jpg_files if p.name != json_path.name]
    jpg_files.sort(key=lambda p: str(p))

    written = 0
    converted = 0
    missing_in_json: list[str] = []
    failed: list[tuple[str, str]] = []

    for p in jpg_files:
        key = p.name
        if key not in mapping:
            missing_in_json.append(str(p))
            continue

        ts, lat, lon = mapping[key]
        try:
            ft = _get_file_type(p)
            if ft == "HEIC" and not args.no_convert_heic:
                _convert_heic_to_jpeg_inplace(p, args.dry_run)
                converted += 1
            _write_exif(p, ts, lat, lon, args.dry_run)
            written += 1
        except Exception as e:
            failed.append((str(p), str(e)))

    print(f"图片总数: {len(jpg_files)}")
    print(f"HEIC->JPEG 转码: {converted}")
    print(f"成功写入 EXIF: {written}")
    print(f"JSON 未匹配到的图片: {len(missing_in_json)}")
    for s in missing_in_json[:50]:
        print("-", s)
    if len(missing_in_json) > 50:
        print(f"... 还有 {len(missing_in_json) - 50} 条未展示")

    print(f"写入失败: {len(failed)}")
    for fp, err in failed[:20]:
        print("-", fp)
        print("  ", err)
    if len(failed) > 20:
        print(f"... 还有 {len(failed) - 20} 条未展示")

    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
