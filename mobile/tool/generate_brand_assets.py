"""Generate deterministic placeholder branding assets for Nursing App."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIZE = 1024
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "branding"

PRIMARY = (0x00, 0x5A, 0x67, 0xFF)
DARK_MARK = (0x7B, 0xD0, 0xDF, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF, 0xFF)
TRANSPARENT = (0x00, 0x00, 0x00, 0x00)


def _inside_cross(x: int, y: int, *, arm: int, thickness: int) -> bool:
    center = SIZE // 2
    half_arm = arm // 2
    half_thickness = thickness // 2
    return (
        center - half_arm <= x <= center + half_arm
        and center - half_thickness <= y <= center + half_thickness
    ) or (
        center - half_thickness <= x <= center + half_thickness
        and center - half_arm <= y <= center + half_arm
    )


def _write_png(
    path: Path,
    *,
    background: tuple[int, int, int, int],
    mark: tuple[int, int, int, int],
    arm: int,
    thickness: int,
) -> None:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            color = (
                mark
                if _inside_cross(x, y, arm=arm, thickness=thickness)
                else background
            )
            rows.extend(color)

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png += chunk(
        b"IHDR",
        struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0),
    )
    png += chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    _write_png(
        OUTPUT_DIR / "app_icon.png",
        background=PRIMARY,
        mark=WHITE,
        arm=500,
        thickness=180,
    )
    _write_png(
        OUTPUT_DIR / "app_icon_foreground.png",
        background=TRANSPARENT,
        mark=WHITE,
        arm=430,
        thickness=150,
    )
    _write_png(
        OUTPUT_DIR / "splash_mark.png",
        background=TRANSPARENT,
        mark=PRIMARY,
        arm=360,
        thickness=120,
    )
    _write_png(
        OUTPUT_DIR / "splash_mark_dark.png",
        background=TRANSPARENT,
        mark=DARK_MARK,
        arm=360,
        thickness=120,
    )


if __name__ == "__main__":
    main()
