#!/usr/bin/env python3
"""
Static navigability check for the generated facility (no Roblox required).

Reads build/mapdata.json (written by `lune run map/build`) and:
  1. rasterises every collidable part that intersects player-body height,
     inflated by the player's radius, onto a 0.5-stud grid
  2. flood-fills walkable space from the first facility spawn
  3. verifies every facility spawn, every room, every corridor and the
     extraction lift zone are reachable, and that no spawn is inside geometry
  4. writes build/plan.svg (floor plan with reachability overlay) and
     build/layout_report.json

Exit code 0 = all checks passed.
"""
import base64
import json
import math
import struct
import sys
import zlib
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = json.loads((ROOT / "build" / "mapdata.json").read_text())

CELL = 0.5
PLAYER_RADIUS = 1.0  # R15 character half-width
SAMPLE_HEIGHTS = (1.0, 2.5, 4.2)  # shins, torso, head (character is ~5 studs)
BODY_BAND = (0.6, 5.0)  # vertical span a walking character occupies above the floor

rooms = DATA["rooms"]
min_x = min(r["cx"] - r["sx"] / 2 for r in rooms) - 6
max_x = max(r["cx"] + r["sx"] / 2 for r in rooms) + 6
min_z = min(r["cz"] - r["sz"] / 2 for r in rooms) - 6
max_z = max(r["cz"] + r["sz"] / 2 for r in rooms) + 6
W = int(math.ceil((max_x - min_x) / CELL))
H = int(math.ceil((max_z - min_z) / CELL))


def to_cell(x, z):
    return int((x - min_x) / CELL), int((z - min_z) / CELL)


def cell_center(i, j):
    return min_x + (i + 0.5) * CELL, min_z + (j + 0.5) * CELL


GATE_PARTS = {"GateLeft", "GateRight"}


def rasterise(gates_open):
    blocked = bytearray(W * H)
    floor_cells = bytearray(W * H)  # cells that have a floor under them
    for part in DATA["collidable"]:
        if part["group"] != "facility":
            continue
        if gates_open and part["name"] in GATE_PARTS:
            continue
        px, py, pz = part["pos"]
        sx, sy, sz = part["size"]
        axes = [part["right"], part["up"], [-v for v in part["look"]]]
        halves = [sx / 2, sy / 2, sz / 2]
        # Vertical extent of the OBB.
        y_extent = sum(abs(axes[k][1]) * halves[k] for k in range(3))
        y_lo, y_hi = py - y_extent, py + y_extent

        is_floor = y_hi <= 0.6 and y_lo >= -1.6
        if is_floor:
            x_extent = sum(abs(axes[k][0]) * halves[k] for k in range(3))
            z_extent = sum(abs(axes[k][2]) * halves[k] for k in range(3))
            i0, j0 = to_cell(px - x_extent, pz - z_extent)
            i1, j1 = to_cell(px + x_extent, pz + z_extent)
            for j in range(max(j0, 0), min(j1 + 1, H)):
                for i in range(max(i0, 0), min(i1 + 1, W)):
                    floor_cells[j * W + i] = 1
            continue

        if y_hi < BODY_BAND[0] or y_lo > BODY_BAND[1]:
            continue
        heights = [h for h in SAMPLE_HEIGHTS if y_lo - 0.01 <= h <= y_hi + 0.01]
        # The part centre always lies inside the part, so thin boards between
        # sample heights (e.g. shelves) are still caught.
        heights.append(min(max(py, BODY_BAND[0]), BODY_BAND[1]))

        expanded = []
        for k in range(3):
            horizontal = math.hypot(axes[k][0], axes[k][2])
            expanded.append(halves[k] + PLAYER_RADIUS * horizontal)
        x_extent = sum(abs(axes[k][0]) * expanded[k] for k in range(3))
        z_extent = sum(abs(axes[k][2]) * expanded[k] for k in range(3))
        i0, j0 = to_cell(px - x_extent, pz - z_extent)
        i1, j1 = to_cell(px + x_extent, pz + z_extent)
        for j in range(max(j0, 0), min(j1 + 1, H)):
            for i in range(max(i0, 0), min(i1 + 1, W)):
                idx = j * W + i
                if blocked[idx]:
                    continue
                cx, cz = cell_center(i, j)
                dx, dz = cx - px, cz - pz
                for hgt in heights:
                    dy = hgt - py
                    inside = True
                    for k in range(3):
                        d = dx * axes[k][0] + dy * axes[k][1] + dz * axes[k][2]
                        if abs(d) > expanded[k]:
                            inside = False
                            break
                    if inside:
                        blocked[idx] = 1
                        break

    walkable = bytearray(W * H)
    for idx in range(W * H):
        walkable[idx] = 1 if floor_cells[idx] and not blocked[idx] else 0
    return blocked, floor_cells, walkable


def flood(walkable, start):
    seen = bytearray(W * H)
    queue = deque()
    if walkable[start[1] * W + start[0]]:
        seen[start[1] * W + start[0]] = 1
        queue.append(start)
    while queue:
        i, j = queue.popleft()
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ni, nj = i + di, j + dj
            if 0 <= ni < W and 0 <= nj < H:
                nidx = nj * W + ni
                if walkable[nidx] and not seen[nidx]:
                    seen[nidx] = 1
                    queue.append((ni, nj))
    return seen


failures = []
spawns = DATA["spawns"]
start = to_cell(spawns[0]["pos"][0], spawns[0]["pos"][2])

# Gates closed (the default state): the lift interior must be sealed off.
_, _, walkable_closed = rasterise(gates_open=False)
seen_closed = flood(walkable_closed, start)

# Gates open (extraction phase): everything must be reachable.
blocked, floor_cells, walkable = rasterise(gates_open=True)
seen = flood(walkable, start)
if not walkable[start[1] * W + start[0]]:
    failures.append(f"start spawn {spawns[0]['room']} is not on walkable space")


def reachable_near(x, z, radius=1.5, seen=seen):
    i0, j0 = to_cell(x - radius, z - radius)
    i1, j1 = to_cell(x + radius, z + radius)
    for j in range(max(j0, 0), min(j1 + 1, H)):
        for i in range(max(i0, 0), min(i1 + 1, W)):
            if seen[j * W + i]:
                return True
    return False


report = {"spawns": [], "rooms": [], "corridors": []}
for s in spawns:
    x, _, z = s["pos"]
    idx_i, idx_j = to_cell(x, z)
    inside_geometry = not walkable[idx_j * W + idx_i]
    ok = reachable_near(x, z, 0.6) and not inside_geometry
    report["spawns"].append({"room": s["room"], "pos": [x, z], "ok": ok})
    if not ok:
        failures.append(f"spawn in {s['room']} at ({x:.1f}, {z:.1f}) is blocked or unreachable")

for r in rooms:
    # A room is reachable if a meaningful share of its floor is reachable.
    total = reach = 0
    i0, j0 = to_cell(r["cx"] - r["sx"] / 2, r["cz"] - r["sz"] / 2)
    i1, j1 = to_cell(r["cx"] + r["sx"] / 2, r["cz"] + r["sz"] / 2)
    for j in range(j0, j1):
        for i in range(i0, i1):
            idx = j * W + i
            if walkable[idx]:
                total += 1
                reach += seen[idx]
    share = reach / total if total else 0
    report["rooms"].append({"id": r["id"], "walkable_cells": total, "reachable_share": round(share, 3)})
    if share < 0.9:
        failures.append(f"room {r['id']}: only {share:.0%} of walkable floor is reachable (isolated pockets)")

for c in DATA["corridors"]:
    mid = (c["s0"] + c["s1"]) / 2
    x, z = (mid, c["at"]) if c["axis"] == "x" else (c["at"], mid)
    ok = reachable_near(x, z)
    report["corridors"].append({"a": c["a"], "b": c["b"], "ok": ok})
    if not ok:
        failures.append(f"corridor {c['a']}->{c['b']} is unreachable")

lift = DATA["liftZone"]
lift_ok = reachable_near(lift["pos"][0], lift["pos"][2], 3)
lift_sealed = not reachable_near(lift["pos"][0], lift["pos"][2], 3, seen=seen_closed)
report["liftZone"] = {"reachableWhenOpen": lift_ok, "sealedWhenClosed": lift_sealed}
if not lift_ok:
    failures.append("extraction lift zone is unreachable with the gates open")
if not lift_sealed:
    failures.append("extraction lift zone is reachable while the gates are closed")

total_walkable = sum(walkable)
total_reached = sum(seen)
report["walkable_cells"] = total_walkable
report["reachable_cells"] = total_reached
report["failures"] = failures
(ROOT / "build" / "layout_report.json").write_text(json.dumps(report, indent=2))

# ---------------------------------------------------------------------------
# Plan render: raster (PNG, embedded) + vector overlay (SVG)
# ---------------------------------------------------------------------------
PX = 2  # pixels per cell
img_w, img_h = W * PX, H * PX
rows = []
for j in range(H):
    row = bytearray()
    for i in range(W):
        idx = j * W + i
        if seen[idx]:
            color = (34, 52, 64)
        elif walkable[idx]:
            color = (200, 110, 30)  # walkable but unreachable: pocket
        elif floor_cells[idx]:
            color = (86, 92, 104)  # geometry footprint
        else:
            color = (14, 16, 20)
        row += bytes(color) * PX
    for _ in range(PX):
        rows.append(bytes(row))


def png(width, height, rows_):
    raw = b"".join(b"\x00" + r for r in rows_)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


raster = base64.b64encode(png(img_w, img_h, rows)).decode()
scale = PX / CELL


def sx(x):
    return (x - min_x) * scale


def sz(z):
    return (z - min_z) * scale


svg = [
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{img_w}" height="{img_h + 60}" '
    f'viewBox="0 0 {img_w} {img_h + 60}" font-family="Helvetica, Arial, sans-serif">',
    f'<rect width="100%" height="100%" fill="#0e1014"/>',
    f'<image x="0" y="0" width="{img_w}" height="{img_h}" href="data:image/png;base64,{raster}"/>',
]
for r in rooms:
    svg.append(
        f'<rect x="{sx(r["cx"] - r["sx"] / 2):.1f}" y="{sz(r["cz"] - r["sz"] / 2):.1f}" '
        f'width="{r["sx"] * scale:.1f}" height="{r["sz"] * scale:.1f}" fill="none" stroke="#38d6f5" stroke-width="2"/>'
    )
    svg.append(
        f'<text x="{sx(r["cx"]):.1f}" y="{sz(r["cz"] - r["sz"] / 2) + 18:.1f}" fill="#bfefff" font-size="13" '
        f'text-anchor="middle" font-weight="700">{r["name"]}</text>'
    )
for p in DATA["props"]:
    color = "#5fe3ff" if p["transformable"] else "#8a93a3"
    svg.append(f'<circle cx="{sx(p["pos"][0]):.1f}" cy="{sz(p["pos"][2]):.1f}" r="2.6" fill="{color}"/>')
for s in report["spawns"]:
    color = "#46f08c" if s["ok"] else "#ff3b3b"
    svg.append(f'<circle cx="{sx(s["pos"][0]):.1f}" cy="{sz(s["pos"][1]):.1f}" r="5" fill="none" stroke="{color}" stroke-width="2.5"/>')
lx, _, lz = lift["pos"]
lsx, _, lsz = lift["size"]
svg.append(
    f'<rect x="{sx(lx - lsx / 2):.1f}" y="{sz(lz - lsz / 2):.1f}" width="{lsx * scale:.1f}" height="{lsz * scale:.1f}" '
    f'fill="#ff3b3b" fill-opacity="0.35" stroke="#ff3b3b" stroke-width="2"/>'
)
status = "ALL CHECKS PASSED" if not failures else f"{len(failures)} FAILURE(S)"
svg.append(
    f'<text x="12" y="{img_h + 24}" fill="#e6eef6" font-size="15" font-weight="700">THE MIMIC PROTOCOL — facility plan · '
    f'{status}</text>'
)
svg.append(
    f'<text x="12" y="{img_h + 46}" fill="#9aa6b6" font-size="12">teal = reachable floor · grey = collidable geometry '
    f'(inflated by player radius) · orange = unreachable pocket · cyan dots = Mimic-transformable props · '
    f'grey dots = decor · green rings = spawns · red = extraction lift zone</text>'
)
svg.append("</svg>")
(ROOT / "build" / "plan.svg").write_text("\n".join(svg))

print(f"grid {W}x{H} @ {CELL} studs, walkable {total_walkable}, reachable {total_reached}")
for r in report["rooms"]:
    print(f"  room {r['id']:<12} reachable {r['reachable_share']:.0%}")
print(f"  spawns ok: {sum(1 for s in report['spawns'] if s['ok'])}/{len(report['spawns'])}, lift reachable when open: {lift_ok}, sealed when closed: {lift_sealed}")
if failures:
    print("FAILURES:")
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("layout check passed")
