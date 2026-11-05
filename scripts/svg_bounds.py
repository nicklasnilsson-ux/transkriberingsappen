"""Var ritningen i en ikon faktiskt ligger, i ikonens 24-rutnät (viewBox).

Material-ikonerna ritas i 0–24 med 2 enheters marginal (ritytan 2–22). En ikon som går ut till kanten
(pan_tool, handen) ser större ut än de andra och nuddar texten under den i Inställningars flikar
(Nicklas 2026-11-05). Används av material_icons.py (som skalar in sådana ikoner) och test_icons.py.

Klarar de kommandon ikonerna använder: M L H V C S Z (stora och små), samt <circle> och <rect>."""
import re

TOKEN = re.compile(r"[MLHVCSZmlhvcsz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?")


def _cubic(p0, p1, p2, p3, steps=24):
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        yield (u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
               u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1])


def path_points(d: str):
    tokens = TOKEN.findall(d)
    i, cmd = 0, None
    x = y = sx = sy = 0.0
    last_ctrl = None

    def num():
        nonlocal i
        value = float(tokens[i])
        i += 1
        return value

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                x, y = sx, sy
                last_ctrl = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = num(), num()
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            sx, sy = x, y
            yield x, y
            cmd = "l" if rel else "L"
            last_ctrl = None
        elif c == "L":
            nx, ny = num(), num()
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            yield x, y
            last_ctrl = None
        elif c == "H":
            n = num()
            x = x + n if rel else n
            yield x, y
            last_ctrl = None
        elif c == "V":
            n = num()
            y = y + n if rel else n
            yield x, y
            last_ctrl = None
        elif c in "CS":
            if c == "C":
                vals = [num() for _ in range(6)]
                if rel:
                    vals = [v + (x if k % 2 == 0 else y) for k, v in enumerate(vals)]
                p1, p2, p3 = (vals[0], vals[1]), (vals[2], vals[3]), (vals[4], vals[5])
            else:
                vals = [num() for _ in range(4)]
                if rel:
                    vals = [v + (x if k % 2 == 0 else y) for k, v in enumerate(vals)]
                p1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl else (x, y)
                p2, p3 = (vals[0], vals[1]), (vals[2], vals[3])
            yield from _cubic((x, y), p1, p2, p3)
            last_ctrl = p2
            x, y = p3
        else:
            raise ValueError(f"Okänt kommando {cmd} i ikonens ritning")


def _attr(tag: str, name: str) -> float:
    m = re.search(rf'\s{name}="([^"]+)"', tag)
    return float(m.group(1)) if m else 0.0


def bounds(svg: str):
    """(vänster, topp, höger, botten) för allt som målas, i viewBox-enheter."""
    xs, ys = [], []
    for tag in re.findall(r"<(?:path|circle|rect)\b[^>]*>", svg):
        if 'fill="none"' in tag:
            continue
        if tag.startswith("<path"):
            for px, py in path_points(re.search(r'\sd="([^"]+)"', tag).group(1)):
                xs.append(px)
                ys.append(py)
        elif tag.startswith("<circle"):
            cx, cy, r = _attr(tag, "cx"), _attr(tag, "cy"), _attr(tag, "r")
            xs += [cx - r, cx + r]
            ys += [cy - r, cy + r]
        else:
            rx, ry, w, h = _attr(tag, "x"), _attr(tag, "y"), _attr(tag, "width"), _attr(tag, "height")
            xs += [rx, rx + w]
            ys += [ry, ry + h]
    return min(xs), min(ys), max(xs), max(ys)


def view_box(svg: str):
    return tuple(float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split())


def bounds_in_grid(svg: str):
    """Ritningen uttryckt i ett 24-rutnät som täcker hela bilden, oavsett viewBox."""
    vx, vy, vw, vh = view_box(svg)
    left, top, right, bottom = bounds(svg)
    return ((left - vx) * 24 / vw, (top - vy) * 24 / vh, (right - vx) * 24 / vw, (bottom - vy) * 24 / vh)
