import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass(frozen=True)
class ExifWritePlan:
    file_path: Path
    exif_datetime: str
    latitude: float
    longitude: float


def _parse_iso8601_to_exif_datetime(value: str) -> str:
    dt = datetime.fromisoformat(value)
    return dt.strftime("%Y:%m:%d %H:%M:%S")


def _load_xichang_images_index(json_path: Path) -> dict[str, ExifWritePlan]:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("events_mock_mannual.json 顶层必须是 JSON 数组")

    target_event = None
    for event in data:
        if not isinstance(event, dict):
            continue
        if event.get("eventId") == "E12":
            target_event = event
            break
        title = str(event.get("title") or "")
        if "西昌" in title and "建昌古城" in title:
            target_event = event
            break

    if target_event is None:
        raise ValueError("未找到西昌建昌古城事件（eventId=E12）")

    images = target_event.get("images")
    if not isinstance(images, list):
        raise ValueError("E12.images 必须是数组")

    index: dict[str, ExifWritePlan] = {}
    for item in images:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        if not isinstance(name, str) or not name.strip():
            continue
        exif_info = item.get("exifInfo")
        if not isinstance(exif_info, dict):
            continue
        ts = exif_info.get("timestamp")
        lat = exif_info.get("latitude")
        lon = exif_info.get("longitude")
        if not isinstance(ts, str) or lat is None or lon is None:
            continue
        try:
            exif_datetime = _parse_iso8601_to_exif_datetime(ts)
            latitude = float(lat)
            longitude = float(lon)
        except Exception:
            continue

        index[name] = ExifWritePlan(
            file_path=Path(),
            exif_datetime=exif_datetime,
            latitude=latitude,
            longitude=longitude,
        )

    if not index:
        raise ValueError("E12 中未找到可用的 exifInfo.timestamp/latitude/longitude")

    return index


def _build_exiftool_args(plan: ExifWritePlan) -> list[str]:
    lat_ref = "N" if plan.latitude >= 0 else "S"
    lon_ref = "E" if plan.longitude >= 0 else "W"
    return [
        "exiftool",
        "-overwrite_original",
        "-DateTimeOriginal={}".format(plan.exif_datetime),
        "-CreateDate={}".format(plan.exif_datetime),
        "-ModifyDate={}".format(plan.exif_datetime),
        "-GPSLatitude={}".format(abs(plan.latitude)),
        "-GPSLatitudeRef={}".format(lat_ref),
        "-GPSLongitude={}".format(abs(plan.longitude)),
        "-GPSLongitudeRef={}".format(lon_ref),
        str(plan.file_path),
    ]


def main() -> int:
    root = Path(__file__).resolve().parent
    json_path = root / "img" / "events_mock_mannual.json"
    img_dir = root / "img" / "西昌建昌古城"
    dry_run = "--dry-run" in set(sys.argv[1:])

    if not json_path.exists():
        print(f"找不到 JSON: {json_path}", file=sys.stderr)
        return 2
    if not img_dir.exists():
        print(f"找不到图片目录: {img_dir}", file=sys.stderr)
        return 2
    if shutil.which("exiftool") is None:
        print("系统未安装 exiftool，无法写入 EXIF", file=sys.stderr)
        return 2

    index = _load_xichang_images_index(json_path)
    image_files = sorted([p for p in img_dir.iterdir() if p.suffix.lower() == ".jpg"])
    if not image_files:
        print(f"目录内没有 .jpg: {img_dir}", file=sys.stderr)
        return 2

    planned = 0
    updated = 0
    skipped = 0

    for file_path in image_files:
        plan = index.get(file_path.name)
        if plan is None:
            skipped += 1
            continue
        plan = ExifWritePlan(
            file_path=file_path,
            exif_datetime=plan.exif_datetime,
            latitude=plan.latitude,
            longitude=plan.longitude,
        )
        planned += 1

        args = _build_exiftool_args(plan)
        if dry_run:
            print(" ".join(args))
            continue

        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode != 0:
            print(
                f"写入失败: {file_path.name}\n{result.stderr.strip() or result.stdout.strip()}",
                file=sys.stderr,
            )
            continue
        updated += 1

    if dry_run:
        print(f"DRY RUN: planned={planned} skipped={skipped}")
        return 0

    print(f"OK: updated={updated} planned={planned} skipped={skipped}")
    return 0 if updated == planned else 1


if __name__ == "__main__":
    raise SystemExit(main())

