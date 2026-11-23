#!/usr/bin/env python3
"""Generate SVG design cheat sheets from docs/design/tokens.json."""
from __future__ import annotations

import json
import re
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "docs" / "design"
TOKENS = json.loads((DESIGN / "tokens.json").read_text(encoding="utf-8"))
PROFILE_SOURCE = (ROOT / "sdk" / "session" / "user_profile.gd").read_text(encoding="utf-8")
THEME_MATCH = re.search(r'^const THEMES = (\{.*\})$', PROFILE_SOURCE, re.MULTILINE)
if THEME_MATCH is None:
    raise RuntimeError("sdk/session/user_profile.gd does not define THEMES")
USER_THEMES = json.loads(THEME_MATCH.group(1))
THEME_LABELS = {"sky": "天空", "violet": "紫罗兰", "rose": "玫瑰", "mint": "薄荷", "orange": "橙色", "gold": "金色"}
C = TOKENS["color"]
M = TOKENS["metric"]
T = TOKENS["type"]
FONT = "Noto Sans SC, PingFang SC, Microsoft YaHei, sans-serif"
STAR = "M49 10Q55 0 61 10L72 31 96 35Q108 37 99 47L82 64 86 88Q88 101 76 95L55 84 34 95Q22 101 24 88L28 64 11 47Q2 37 14 35L38 31Z"


def defs() -> str:
    sky_defs = []
    for item in TOKENS["sky_anchors"]:
        sky_defs.append(
            f'<linearGradient id="sky-{item["hour"]}" x2="0" y2="1">'
            f'<stop stop-color="{item["top"]}"/><stop offset="1" stop-color="{item["bottom"]}"/>'
            "</linearGradient>"
        )
    return f'''<defs>
<linearGradient id="gold" x2="0.2" y2="1"><stop stop-color="{C['star.soft']}"/><stop offset="0.5" stop-color="{C['star']}"/><stop offset="1" stop-color="{C['star.lip']}"/></linearGradient>
{''.join(sky_defs)}
<path id="star-shape" d="{STAR}"/>
<g id="i-check" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="m4 12 5 5L21 5"/></g>
<g id="i-plus" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round"><path d="M12 3v18M3 12h18"/></g>
<g id="i-close" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round"><path d="m5 5 14 14M19 5 5 19"/></g>
<g id="i-arrow" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18m-7-7 7 7-7 7"/></g>
<g id="i-back" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12H3m7-7-7 7 7 7"/></g>
<g id="i-search" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round"><circle cx="10" cy="10" r="7"/><path d="m15 15 7 7"/></g>
<g id="i-gear" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linejoin="round"><path d="m9 2 6 0 1 4 4 1 3 5-3 4-1 4-5 2-4-2-4-1-3-5 2-4 1-3 4-1Z"/><circle cx="12" cy="12" r="4"/></g>
<g id="i-qr" fill="none" stroke="currentColor" stroke-width="{M['stroke']}"><path d="M2 2h7v7H2zM15 2h7v7h-7zM2 15h7v7H2zM15 15h3v3h-3zM20 15h2v7h-7v-2"/></g>
<g id="i-bluetooth" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="M11 2v20l7-6-12-9m5 8 7-7-7-6"/></g>
<g id="i-keyboard" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linejoin="round"><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M5 9h2m2 0h2m2 0h2m2 0h2M5 13h2m2 0h2m2 0h2m2 0h2M7 16h10"/></g>
<g id="i-info" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/></g>
<g id="i-warn" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 22 21H2Z"/><path d="M12 9v5M12 18h.01"/></g>
<g id="i-clock" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v6l4 2"/></g>
<g id="i-sound" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10v4h4l5 4V6L7 10Z"/><path d="M16 9q3 3 0 6m3-9q6 6 0 12"/></g>
<g id="i-phone" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linejoin="round"><rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/></g>
<g id="i-eye" fill="none" stroke="currentColor" stroke-width="{M['stroke']}" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12q10-11 20 0-10 11-20 0Z"/><circle cx="12" cy="12" r="3"/></g>
</defs>'''


class Board:
    def __init__(self, width: int, height: int, title: str):
        self.width = width
        self.height = height
        self.title = title
        self.parts: list[str] = []

    def raw(self, value: str) -> None:
        self.parts.append(value)

    def rect(self, x, y, w, h, fill, r=0, stroke=None, sw=None, opacity=1) -> None:
        border = ""
        if stroke:
            border = f' stroke="{stroke}" stroke-width="{sw if sw is not None else M["stroke"]}"'
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" opacity="{opacity}"{border}/>')

    def line(self, x1, y1, x2, y2, color, sw=None, dash=None) -> None:
        dashed = f' stroke-dasharray="{dash}"' if dash else ""
        self.raw(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{sw if sw is not None else M["stroke"]}" stroke-linecap="round"{dashed}/>')

    def circle(self, x, y, r, fill, stroke=None, sw=None, opacity=1) -> None:
        border = ""
        if stroke:
            border = f' stroke="{stroke}" stroke-width="{sw if sw is not None else M["stroke"]}"'
        self.raw(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" opacity="{opacity}"{border}/>')

    def path(self, d, fill="none", stroke=None, sw=None, opacity=1) -> None:
        border = ""
        if stroke:
            border = f' stroke="{stroke}" stroke-width="{sw if sw is not None else M["stroke"]}" stroke-linecap="round" stroke-linejoin="round"'
        self.raw(f'<path d="{d}" fill="{fill}" opacity="{opacity}"{border}/>')

    def text(self, x, y, value, size=None, color=None, weight=None, anchor="start") -> None:
        size = size if size is not None else T["size.body"]
        color = color or C["ink"]
        weight = weight if weight is not None else T["weight.body"]
        self.raw(
            f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
            f'fill="{color}" text-anchor="{anchor}">{escape(str(value))}</text>'
        )

    def multiline(self, x, y, values, size=None, color=None, weight=None, gap=None, anchor="start") -> None:
        size = size if size is not None else T["size.body"]
        gap = gap if gap is not None else size + M["grid"] * 2
        for i, value in enumerate(values):
            self.text(x, y + i * gap, value, size, color, weight, anchor)

    def use(self, icon, x, y, scale=1, color=None) -> None:
        self.raw(f'<use href="#{icon}" transform="translate({x} {y}) scale({scale})" color="{color or C["ink"]}"/>')

    def star(self, x, y, scale=1, mood="happy", angle=0, gradient=True) -> None:
        self.raw(f'<g transform="translate({x} {y}) scale({scale}) rotate({angle} 55 55)">')
        self.raw(f'<use href="#star-shape" transform="translate(0 {M["lip"]})" fill="{C["star.lip"]}"/>')
        fill = "url(#gold)" if gradient else C["star"]
        self.raw(f'<use href="#star-shape" fill="{fill}" stroke="{C["ink"]}" stroke-width="{M["stroke"]}"/>')
        self.path("M20 39 39 36 49 17", "none", C["white"], M["stroke"], 0.7)
        if mood == "celebrate":
            self.path("m35 44 7 5-7 5m39-10-7 5 7 5", "none", C["ink"], M["stroke"])
        else:
            self.circle(42 if mood == "waiting" else 41, 49, 3, C["ink"])
            self.circle(69 if mood == "waiting" else 68, 49, 3, C["ink"])
        if mood == "waiting":
            self.path("M48 65q8 4 15 0", "none", C["ink"], M["stroke"])
        else:
            self.path("M43 61h24Q57 82 43 61Z", C["pink"], C["ink"], M["stroke"])
        self.circle(31, 60, 4, C["pink"], opacity=0.55)
        self.circle(79, 60, 4, C["pink"], opacity=0.55)
        self.raw("</g>")

    def panel(self, x, y, w, h, title, subtitle=None) -> None:
        self.rect(x, y + M["lip"], w, h, C["line.lip"], M["radius.card"])
        self.rect(x, y, w, h, C["panel"], M["radius.card"], C["line"], M["stroke"])
        self.text(x + 24, y + 38, title, T["size.section"], C["ink"], T["weight.title"])
        if subtitle:
            self.text(x + 24, y + 66, subtitle, T["size.meta"], C["muted"], T["weight.body"])

    def header(self, index, title, subtitle) -> None:
        self.rect(0, 0, self.width, self.height, C["page"])
        self.rect(0, 0, self.width, 104, C["sky"])
        self.circle(54, 52, 30, C["star"])
        self.text(54, 60, index, T["size.meta"], C["ink"], T["weight.title"], "middle")
        self.text(100, 47, title, T["size.title"], C["white"], T["weight.title"])
        self.text(100, 78, subtitle, T["size.meta"], C["sky.soft"], T["weight.body"])
        self.text(self.width - 40, 62, f'{TOKENS["brand"]} · v{TOKENS["version"]}', T["size.meta"], C["white"], T["weight.label"], "end")

    def footer(self, label) -> None:
        self.text(40, self.height - 20, f'{TOKENS["brand"]} · {TOKENS["direction"]}', T["size.meta"], C["muted"], T["weight.body"])
        self.text(self.width - 40, self.height - 20, label, T["size.meta"], C["muted"], T["weight.label"], "end")

    def focus(self, x, y, w, h, radius) -> None:
        ring = M["focus.ring"]
        edge = M["focus.gap"] + ring
        for spread, opacity in ((edge + 4, 0.10), (edge + 2, 0.20)):
            offset = spread - 1
            self.rect(x - offset, y - offset + 1, w + offset * 2, h + offset * 2, "none", radius + offset, C["focus"], 2, opacity)
        offset = edge - ring / 2
        self.rect(x - offset, y - offset, w + offset * 2, h + offset * 2, "none", radius + offset, C["focus"], ring)

    def button(self, x, y, w, label, kind="primary", state="default", h=None, size=None, icon=None) -> None:
        h = h or M["button.height"]
        size = size or T["size.button"]
        spec = TOKENS["button"]["disabled" if state == "disabled" else kind]
        face = C[spec["fill"]]
        lip = C[spec["lip"]] if spec["lip"] else None
        text_color = C[spec["text"]]
        border = C[spec["border"]] if spec["border"] else None
        if state == "focus":
            self.focus(x, y, w, h + M["lip"], M["radius.button"])
        pressed = state == "pressed"
        face_y = y + (M["lip"] if pressed else 0)
        if lip and not pressed:
            self.rect(x, y + M["lip"], w, h, lip, M["radius.button"])
        self.rect(x, face_y, w, h, face, M["radius.button"], border, M["stroke"])
        if icon:
            self.use(icon, x + 20, face_y + h / 2 - 12, 1, text_color)
            self.text(x + 54, face_y + h / 2 + size * 0.35, label, size, text_color, T["weight.label"])
        else:
            self.text(x + w / 2, face_y + h / 2 + size * 0.35, label, size, text_color, T["weight.label"], "middle")

    def switch(self, x, y, on=True) -> None:
        fill = C["sky"] if on else C["disabled"]
        self.rect(x, y, M["switch.width"], M["switch.height"], fill, M["radius.chip"])
        knob_x = x + M["switch.width"] - M["switch.height"] / 2 if on else x + M["switch.height"] / 2
        self.circle(knob_x, y + M["switch.height"] / 2, M["switch.height"] / 2 - M["grid"], C["white"])

    def input(self, x, y, w, value, focused=False) -> None:
        border = C["sky"] if focused else C["line.lip"]
        stroke = M["stroke"] + 1 if focused else M["stroke"]
        self.rect(x, y, w, M["button.height"], C["panel"], M["radius.input"], border, stroke)
        self.text(x + 18, y + M["button.height"] / 2 + T["size.body"] * 0.35, value, T["size.body"], C["ink"], T["weight.body"])

    def progress(self, x, y, w, value=0.68) -> None:
        h = M["progress.height"]
        radius = M["grid"] * 2
        self.rect(x, y, w, h, C["line"], radius)
        self.rect(x, y, w * value, h, C["star.lip"], radius)
        self.rect(x, y, w * value, h - M["lip"], C["star"], radius)

    def avatar(self, x, y, size, fill=None, selected=False, mood="happy") -> None:
        face = C["sky.soft"] if selected else (fill or C["panel"])
        edge = C["sky"] if selected else C["line.lip"]
        self.rect(x, y + M["lip"], size, size, edge, M["radius.card"])
        self.rect(x, y, size, size, face, M["radius.card"], edge, M["stroke"])
        self.star(x + size * 0.2, y + size * 0.19, size / 170, mood, -5, gradient=False)
        if selected:
            self.circle(x + size - 8, y + 8, 14, C["success"])
            self.use("i-check", x + size - 20, y - 4, 1, C["white"])

    def svg(self) -> str:
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{self.height}" '
            f'viewBox="0 0 {self.width} {self.height}" role="img" aria-label="{escape(self.title)}">\n'
            + defs()
            + "\n"
            + "\n".join(self.parts)
            + "\n</svg>\n"
        )


def foundations() -> Board:
    b = Board(1600, 1200, f'星星大作战 v{TOKENS["version"]} 基础规范')
    b.header("01", "基础规范", "品牌、色彩、天空、字体、间距与果冻厚度")

    b.panel(32, 128, 520, 300, "品牌与星星角色", "果冻星星保留金色渐变，其他组件使用纯色块")
    for i, (mood, label) in enumerate((("happy", "开心"), ("waiting", "等待"), ("celebrate", "庆祝"))):
        x = 70 + i * 158
        b.star(x, 222, 1.12, mood, (-5, 3, 6)[i])
        b.text(x + 62, 388, label, T["size.meta"], C["ink"], T["weight.label"], "middle")

    b.panel(572, 128, 996, 300, "全部颜色", "名称与十六进制值直接读取 tokens.json")
    palette = list(C.items())
    cols = 7
    sw, sh = 126, 42
    for i, (name, color) in enumerate(palette):
        col, row = i % cols, i // cols
        x, y = 596 + col * 136, 220 + row * 48
        border = C["line.lip"] if color in (C["white"], C["panel"], C["page"]) else None
        b.rect(x, y, sw, sh, color, M["radius.input"], border, M["stroke"])
        text_color = C["white"] if name in ("sky", "sky.lip", "ink", "muted", "success", "danger", "scrim") else C["ink"]
        b.text(x + 7, y + 17, name, 12, text_color, T["weight.label"])
        b.text(x + 7, y + 34, color, 11, text_color, T["weight.body"])

    b.panel(32, 452, 648, 252, "插图配色", "渐变仅用于装饰，不改变控件语义")
    for i, item in enumerate(TOKENS["sky_anchors"]):
        x = 56 + i * 150
        b.rect(x, 528, 132, 112, f'url(#sky-{item["hour"]})', M["radius.card"])
        b.text(x + 66, 574, f'{item["hour"]:02d}:00', T["size.meta"], C["white"], T["weight.label"], "middle")
        b.text(x + 66, 620, f'{item["top"]} →', 13, C["white"], T["weight.body"], "middle")
        b.text(x + 66, 638, item["bottom"], 13, C["white"], T["weight.body"], "middle")
    b.text(56, 674, "首页使用固定的纯蓝展台，保持标题对比。", T["size.meta"], C["muted"])

    b.panel(704, 452, 448, 252, "字号与字重阶梯")
    type_rows = [
        ("展示 48 / 800", T["size.display"], T["weight.title"]),
        ("标题 32 / 800", T["size.title"], T["weight.title"]),
        ("分区 24 / 700", T["size.section"], T["weight.label"]),
        ("正文 22 / 500", T["size.body"], T["weight.body"]),
        ("说明 18 / 500", T["size.meta"], T["weight.body"]),
    ]
    for (label, size, weight), yy in zip(type_rows, (556, 602, 640, 672, 698)):
        b.text(730, yy, label, size, C["ink"], weight)

    b.panel(1176, 452, 392, 252, "间距：4 的倍数")
    for i, amount in enumerate((4, 8, 12, 16, 24, 32, 48)):
        y = 514 + i * 22
        b.text(1200, y + 14, str(amount), 14, C["muted"], T["weight.label"], "end")
        b.rect(1216, y, amount * 5, 16, C["sky"], M["grid"])
    b.text(1200, 698, f'基础网格 = {M["grid"]}', 14, C["muted"], T["weight.label"])

    b.panel(32, 728, 760, 404, "圆角与组件尺寸")
    radii = [
        ("button", M["radius.button"], "按钮 16"),
        ("card", M["radius.card"], "卡片 20"),
        ("sheet", M["radius.sheet"], "弹层 24"),
        ("input", M["radius.input"], "输入 14"),
    ]
    for i, (_, radius, label) in enumerate(radii):
        x = 64 + i * 174
        b.rect(x, 808, 146, 96, C["sky.soft"], radius, C["sky"], M["stroke"])
        b.text(x + 73, 942, label, T["size.meta"], C["ink"], T["weight.label"], "middle")
    b.text(64, 1004, f'按钮高 {M["button.height"]} / 大按钮 {M["button.height.large"]} / 小按钮 {M["button.height.small"]}', T["size.body"], C["ink"], T["weight.label"])
    b.text(64, 1042, f'最小触控 {M["hit.min"]} · 行高 {M["row.height"]} · 页面边距 {M["page.margin"]}', T["size.meta"], C["muted"])
    b.text(64, 1080, f'开关 {M["switch.width"]}×{M["switch.height"]} · 进度条高 {M["progress.height"]}', T["size.meta"], C["muted"])

    b.panel(816, 728, 752, 404, "描边、厚底边与按下")
    # Enlarged construction diagram: 2-unit stroke, 4-unit lip, 4-unit press offset.
    b.text(850, 806, "静止", T["size.section"], C["ink"], T["weight.label"])
    b.rect(850, 844 + M["lip"] * 4, 260, 104, C["star.lip"], M["radius.button"])
    b.rect(850, 844, 260, 104, C["star"], M["radius.button"], C["ink"], M["stroke"])
    b.line(1132, 844, 1182, 844, C["ink"], M["stroke"])
    b.text(1194, 851, f'描边 {M["stroke"]}', T["size.meta"], C["ink"], T["weight.label"])
    b.line(1132, 948, 1182, 948 + M["lip"] * 4, C["star.lip"], M["stroke"])
    b.text(1194, 974, f'厚底边 {M["lip"]}', T["size.meta"], C["ink"], T["weight.label"])
    b.text(850, 1018, "按下", T["size.section"], C["ink"], T["weight.label"])
    b.rect(850, 1050 + M["lip"], 260, 56, C["star"], M["radius.button"], C["ink"], M["stroke"])
    b.line(1132, 1050, 1132, 1050 + M["lip"] * 4, C["focus"], M["stroke"])
    b.text(1152, 1080, f'按下下沉 {M["lip"]}，lip 消失', T["size.meta"], C["ink"], T["weight.label"])
    b.footer("FOUNDATIONS")
    return b


def game_card(b: Board, x, y, w, title, selected=False, focused=False, plus=False) -> None:
    h = 122 if w <= 240 else 138
    if focused:
        b.focus(x, y, w, h + M["lip"], M["radius.card"])
    lip = C["selection.lip"] if selected else C["line.lip"]
    b.rect(x, y + M["lip"], w, h, lip, M["radius.card"])
    b.rect(x, y, w, h, C["sky.soft"] if selected else C["panel"], M["radius.card"], lip if selected else C["line"], M["stroke"])
    if plus:
        b.circle(x + w / 2, y + 54, 30, C["sky.soft"])
        b.use("i-plus", x + w / 2 - 12, y + 42, 1, C["sky"])
        b.text(x + w / 2, y + 112, title, T["size.meta"], C["sky"], T["weight.label"], "middle")
    else:
        if w <= 240:
            b.rect(x + 14, y + 14, 54, 54, C["sky"], M["radius.input"])
            b.star(x + 17, y + 17, 0.45, "happy", -8, gradient=False)
            b.text(x + 80, y + 42, title, T["size.meta"], C["ink"], T["weight.title"])
            b.text(x + 80, y + 66, "2–4 人", 14, C["muted"])
            b.text(x + 14, y + 112, "约 5 分钟", 14, C["muted"], T["weight.label"])
        else:
            b.rect(x + 14, y + 14, 82, 82, C["sky"], M["radius.input"])
            b.star(x + 19, y + 18, 0.7, "happy", -8, gradient=False)
            b.text(x + 112, y + 50, title, T["size.section"], C["ink"], T["weight.title"])
            b.text(x + 112, y + 82, "2–4 人 · 约 5 分钟", T["size.meta"], C["muted"])
        if selected:
            b.circle(x + w - 26, y + 26, 14, C["sky"])
            b.use("i-check", x + w - 35, y + 17, 0.75, C["white"])


def banner(b: Board, x, y, w, label, kind) -> None:
    specs = {
        "info": (C["sky.soft"], C["sky"], "i-info"),
        "success": (C["success.soft"], C["success"], "i-check"),
        "danger": (C["danger.soft"], C["danger"], "i-warn"),
        "wait": (C["star.soft"], C["ink"], "i-clock"),
    }
    fill, color, icon = specs[kind]
    b.rect(x, y, w, M["row.height"], fill, M["radius.input"], color, M["stroke"])
    b.use(icon, x + 18, y + 22, 1, color)
    b.text(x + 58, y + 42, label, T["size.meta"], color, T["weight.label"])


def components() -> Board:
    b = Board(1600, 1500, f'星星大作战 v{TOKENS["version"]} 组件规范')
    b.header("02", "组件规范", "纯色果冻组件、厚底边、电视焦点与完整状态")

    b.panel(32, 124, 1536, 500, "按钮：4 种 × 4 状态", "焦点使用细蓝环与略向下的淡蓝投影，保留按钮厚底边")
    kinds = [("primary", "PRIMARY / 星黄"), ("accent", "ACCENT / 天蓝"), ("secondary", "SECONDARY / 白底"), ("danger", "DANGER / 危险")]
    states = [("default", "默认"), ("pressed", "按下"), ("focus", "电视焦点"), ("disabled", "禁用")]
    for j, (state, state_label) in enumerate(states):
        b.text(416 + j * 282, 222, state_label, T["size.meta"], C["muted"], T["weight.label"], "middle")
    for i, (kind, label) in enumerate(kinds):
        y = 248 + i * 88
        b.text(60, y + 40, label, T["size.meta"], C["ink"], T["weight.label"])
        for j, (state, state_label) in enumerate(states):
            b.button(300 + j * 282, y, 232, label.split(" /")[0], kind, state, M["button.height.small"], T["size.meta"])

    b.panel(32, 650, 492, 370, "游戏封面卡片", "默认 / 选中 / 焦点")
    game_card(b, 58, 738, 202, "星星棋")
    game_card(b, 288, 738, 202, "连连看", selected=True)
    game_card(b, 58, 874, 432, "电视焦点卡", focused=True)

    b.panel(548, 650, 492, 370, "设置、输入与进度")
    for i, (label, on) in enumerate((("音效", True), ("触感反馈", False))):
        y = 724 + i * M["row.height"]
        b.text(574, y + 39, label, T["size.body"], C["ink"], T["weight.label"])
        b.switch(944, y + 14, on)
    b.text(574, 872, "名字输入", T["size.meta"], C["muted"], T["weight.label"])
    b.input(574, 888, 204, "小星", False)
    b.input(806, 888, 204, "正在编辑", True)
    b.text(574, 982, "加载进度 68%", T["size.meta"], C["muted"], T["weight.label"])
    b.progress(806, 990, 204)

    b.panel(1064, 650, 504, 370, "提示横幅", "信息 / 成功 / 危险 / 等待")
    banner(b, 1090, 738, 452, "已找到附近的游戏", "info")
    banner(b, 1090, 808, 452, "加入成功，准备开玩！", "success")
    banner(b, 1090, 878, 452, "连接失败，请重试", "danger")
    banner(b, 1090, 948, 452, "正在等待房主确认", "wait")

    b.panel(32, 1046, 560, 382, "底部弹层 sheet")
    b.rect(58, 1120, 508, 280, C["scrim"], M["radius.card"], opacity=0.25)
    b.rect(58, 1210 + M["lip"], 508, 190, C["line.lip"], M["radius.sheet"])
    b.rect(58, 1210, 508, 190, C["panel"], M["radius.sheet"], C["line"], M["stroke"])
    b.rect(264, 1224, 96, M["grid"], C["line.lip"], M["radius.chip"])
    b.text(84, 1270, "选择加入方式", T["size.section"], C["ink"], T["weight.title"])
    b.button(84, 1300, 214, "扫码加入", "accent", "default", M["button.height.small"], T["size.meta"], "i-qr")
    b.button(322, 1300, 218, "手动输入", "secondary", "default", M["button.height.small"], T["size.meta"], "i-keyboard")

    b.panel(616, 1046, 472, 382, "房间列表行")
    for i, (name, meta, available) in enumerate((("小星的房间", "星星棋 · 1 / 2 人", True), ("月月的房间", "连连看 · 2 / 2 人", False), ("云朵的房间", "你画我猜 · 3 / 4 人", True))):
        y = 1120 + i * 92
        b.rect(642, y + M["lip"], 420, 76, C["line.lip"], M["radius.input"])
        b.rect(642, y, 420, 76, C["panel"], M["radius.input"], C["line"], M["stroke"])
        b.circle(678, y + 38, 24, C["sky.soft"])
        b.star(660, y + 20, 0.34, "happy", -5, gradient=False)
        b.text(714, y + 31, name, T["size.meta"], C["ink"], T["weight.label"])
        b.text(714, y + 57, meta, 14, C["muted"], T["weight.body"])
        b.text(1040, y + 44, "可加入" if available else "已满", 14, C["success"] if available else C["disabled.text"], T["weight.label"], "end")

    b.panel(1112, 1046, 456, 382, "头像角色格", "选中项带对勾；运行时使用动物头像")
    avatar_fills = [C["sky.soft"], C["star.soft"], C["success.soft"], C["danger.soft"], C["purple"], C["mint"]]
    avatar_names = ["小熊", "狐狸", "兔子", "小猫", "小狗", "熊猫"]
    for i in range(6):
        x = 1140 + (i % 3) * 132
        y = 1136 + (i // 3) * 112
        b.avatar(x, y, 78, avatar_fills[i], selected=i == 1, mood=("happy", "waiting", "celebrate")[i % 3])
        b.text(x + 39, y + 100, avatar_names[i], 14, C["ink"], T["weight.label"], "middle")
    b.text(1140, 1404, "头像来源：assets/ui/characters.json", 12, C["muted"], T["weight.body"])
    b.footer("COMPONENTS")
    return b


def phone_start(b: Board, x, y, scale, label) -> None:
    b.raw(f'<g transform="translate({x} {y}) scale({scale})">')
    b.rect(0, M["lip"] * 2, 540, 960, C["line.lip"], 48)
    b.rect(0, 0, 540, 960, C["panel"], 48, C["ink"], M["stroke"])
    b.rect(12, 12, 516, 936, C["page"], 40)
    b.rect(220, 22, 100, 12, C["ink"], M["radius.chip"])
    b.text(270, 74, label, T["size.meta"], C["muted"], T["weight.label"], "middle")


def phone_end(b: Board) -> None:
    b.raw("</g>")


def screen_home(b: Board, x, y, scale) -> None:
    phone_start(b, x, y, scale, "首页")
    b.star(36, 91, .27, "happy", -5, gradient=False)
    b.text(76, 115, TOKENS["brand"], T["size.section"], C["ink"], T["weight.title"])
    b.text(494, 115, "本地联机", T["size.meta"], C["sky.lip"], T["weight.label"], "end")
    b.rect(36, 156, 468, 404, C["sky.lip"], 28)
    b.rect(36, 152, 468, 404, C["sky"], 28)
    b.text(64, 197, "派对街机", T["size.meta"], C["star"], T["weight.title"])
    b.multiline(64, 258, ["朋友齐了，", "开一局！"], 42, C["white"], gap=55)
    b.text(64, 352, "和身边的朋友一起玩，不用注册。", T["size.meta"], C["white"])
    b.star(186, 374, 1.35, "happy", -7)
    b.text(36, 604, "现在开玩", T["size.meta"], C["sky.lip"], T["weight.title"])
    b.button(36, 624, 468, "选择游戏", "primary", "default", M["button.height.large"])
    b.button(36, 726, 468, "加入游戏", "secondary", "default", M["button.height.large"])
    b.button(36, 861, 228, "用户信息", "secondary", "default", M["button.height.small"], T["size.meta"])
    b.button(276, 861, 228, "设置", "secondary", "default", M["button.height.small"], T["size.meta"])
    phone_end(b)


def screen_games(b: Board, x, y, scale) -> None:
    phone_start(b, x, y, scale, "选择游戏")
    b.text(36, 108, "发起游戏", T["size.meta"], C["sky.lip"], T["weight.title"])
    b.text(36, 159, "选择游戏", T["size.title"], C["ink"], T["weight.title"])
    b.text(36, 213, "挑一个喜欢的游戏，再邀请朋友。", T["size.body"], C["muted"])
    game_card(b, 36, 258, 218, "五子棋", selected=True)
    game_card(b, 286, 258, 218, "添加游戏", plus=True)
    b.text(36, 748, "已选择：五子棋", T["size.meta"], C["muted"], T["weight.label"])
    b.button(36, 776, 468, "启动游戏", "primary", "default", M["button.height.large"])
    b.button(36, 874, 468, "返回", "secondary", "default", M["button.height.small"])
    phone_end(b)


def room_row(b: Board, y, title, meta, open_room=True) -> None:
    b.rect(36, y + M["lip"], 468, 92, C["line.lip"], M["radius.card"])
    b.rect(36, y, 468, 92, C["panel"], M["radius.card"], C["line"], M["stroke"])
    b.circle(82, y + 46, 30, C["sky.soft"])
    b.star(60, y + 24, 0.42, "happy", -5, gradient=False)
    b.text(128, y + 38, title, T["size.body"], C["ink"], T["weight.label"])
    b.text(128, y + 68, meta, T["size.meta"], C["muted"])
    b.text(476, y + 54, "可加入" if open_room else "已满", T["size.meta"], C["success"] if open_room else C["disabled.text"], T["weight.label"], "end")


def screen_join(b: Board, x, y, scale) -> None:
    phone_start(b, x, y, scale, "加入游戏")
    b.text(36, 108, "加入游戏", T["size.meta"], C["sky.lip"], T["weight.title"])
    b.text(36, 159, "加入朋友的游戏", T["size.title"], C["ink"], T["weight.title"])
    b.button(36, 210, 468, "扫码加入", "accent", "default", M["button.height.small"], icon="i-qr")
    b.button(36, 288, 468, "手动输入", "secondary", "default", M["button.height.small"], icon="i-keyboard")
    b.button(36, 366, 468, "蓝牙", "secondary", "default", M["button.height.small"], icon="i-bluetooth")
    b.text(36, 488, "附近的游戏", T["size.section"], C["ink"], T["weight.title"])
    b.text(504, 488, "重新搜索", T["size.meta"], C["sky"], T["weight.label"], "end")
    room_row(b, 518, "五子棋", "客厅电视 · 局域网", True)
    room_row(b, 630, "蓝牙游戏", "附近设备 · 3BA4", True)
    b.button(36, 874, 468, "返回", "secondary", "default", M["button.height.small"])
    phone_end(b)


def setting_row(b: Board, y, label, detail=None, on=None) -> None:
    b.rect(36, y, 468, M["row.height"], C["panel"], M["radius.input"], C["line"], M["stroke"])
    b.text(58, y + 42, label, T["size.body"], C["ink"], T["weight.label"])
    if on is not None:
        b.switch(424, y + 16, on)
    elif detail:
        b.text(476, y + 42, detail, T["size.meta"], C["muted"], T["weight.body"], "end")
        b.use("i-arrow", 480, y + 22, 0.8, C["muted"])


def screen_settings(b: Board, x, y, scale) -> None:
    phone_start(b, x, y, scale, "设置")
    b.text(36, 126, "设置", T["size.title"], C["ink"], T["weight.title"])
    setting_row(b, 168, "语言", "简体中文")
    setting_row(b, 256, "音效", on=True)
    setting_row(b, 344, "触感反馈", on=True)
    setting_row(b, 432, "减少动态效果", on=False)
    b.multiline(36, 548, ["触感仅在手机生效。", "音效与震动可分别关闭。", "减少动态后使用静态星光。"], T["size.meta"], C["muted"], gap=32)
    b.button(36, 820, 468, "完成", "primary", "default", M["button.height.large"])
    phone_end(b)


def option_card(b: Board, x, y, w, label, color, selected=False, compact=False) -> None:
    h = 52 if compact else 58
    lip = C["sky"] if selected else C["line.lip"]
    fill = C["sky.soft"] if selected else C["panel"]
    b.rect(x, y + M["lip"], w, h, lip, M["radius.input"])
    b.rect(x, y, w, h, fill, M["radius.input"], C["sky"] if selected else C["line"], M["stroke"])
    b.circle(x + 24, y + h / 2, 12, color)
    b.text(x + 44, y + h / 2 + 6, label, 15 if compact else T["size.meta"], C["ink"], T["weight.label"])
    if selected:
        b.circle(x + w - 18, y + 18, 11, C["success"])
        b.use("i-check", x + w - 28, y + 8, 0.82, C["white"])


def screen_profile(b: Board, x, y, scale) -> None:
    phone_start(b, x, y, scale, "用户信息")
    b.text(36, 112, "用户信息", T["size.title"], C["ink"], T["weight.title"])
    b.avatar(36, 132, 94, C["sky.soft"], True)
    b.text(154, 152, "你的名字", T["size.meta"], C["muted"], T["weight.label"])
    b.input(154, 164, 350, "小星", True)
    b.text(36, 260, "角色", T["size.section"], C["ink"], T["weight.title"])
    fills = [C["sky.soft"], C["star.soft"], C["success.soft"], C["danger.soft"], C["purple"], C["mint"]]
    for i in range(6):
        b.avatar(36 + i * 78, 278, 60, fills[i], i == 0, ("happy", "waiting", "celebrate")[i % 3])
    b.text(36, 376, "配色", T["size.section"], C["ink"], T["weight.title"])
    palette_options = [("蜂蜜", C["star"]), ("莓果", C["pink"]), ("薄荷", C["mint"]), ("海盐", C["sky.soft"])]
    for i, (label, color) in enumerate(palette_options):
        option_card(b, 36 + (i % 2) * 238, 394 + (i // 2) * 66, 220, label, color, selected=i == 0)
    b.text(36, 548, "主题色", T["size.section"], C["ink"], T["weight.title"])
    theme_options = [(THEME_LABELS[key], "#" + USER_THEMES[key]) for key in ("sky", "violet", "rose", "mint", "orange", "gold")]
    for i, (label, color) in enumerate(theme_options):
        option_card(b, 36 + (i % 2) * 238, 566 + (i // 2) * 60, 220, label, color, selected=i == 0, compact=True)
    b.button(36, 796, 226, "取消", "secondary", "default", M["button.height.large"])
    b.button(278, 796, 226, "保存", "primary", "default", M["button.height.large"])
    phone_end(b)


def screens() -> Board:
    b = Board(1900, 1300, f'星星大作战 v{TOKENS["version"]} 手机与电视屏幕')
    b.header("03", "关键屏幕", "手机逻辑画布 540×960 等比缩小并排；电视逻辑画布 1280×720")
    scale = 0.58
    xs = [42, 410, 778, 1146, 1514]
    screen_home(b, xs[0], 126, scale)
    screen_games(b, xs[1], 126, scale)
    screen_join(b, xs[2], 126, scale)
    screen_settings(b, xs[3], 126, scale)
    screen_profile(b, xs[4], 126, scale)

    b.text(42, 716, "首页", T["size.meta"], C["ink"], T["weight.label"])
    b.text(410, 716, "选择游戏", T["size.meta"], C["ink"], T["weight.label"])
    b.text(778, 716, "加入游戏", T["size.meta"], C["ink"], T["weight.label"])
    b.text(1146, 716, "设置", T["size.meta"], C["ink"], T["weight.label"])
    b.text(1514, 716, "用户信息", T["size.meta"], C["ink"], T["weight.label"])

    # TV home screen, authored at its native 1280×720 and scaled uniformly.
    tv_scale = 0.64
    tv_x, tv_y = 540, 778
    b.raw(f'<g transform="translate({tv_x} {tv_y}) scale({tv_scale})">')
    b.rect(0, M["lip"] * 2, 1280, 720, C["sky.lip"], M["radius.card"])
    b.rect(0, 0, 1280, 720, C["page"], M["radius.card"], C["ink"], M["stroke"])
    b.text(56, 76, TOKENS["brand"], T["size.title"], C["ink"], T["weight.title"])
    b.text(1224, 76, "本地联机", T["size.meta"], C["sky.lip"], T["weight.label"], "end")
    b.rect(84, 145, 570, 420, C["sky.lip"], 28)
    b.rect(84, 141, 570, 420, C["sky"], 28)
    b.text(120, 209, "派对街机", T["size.body"], C["star"], T["weight.title"])
    b.multiline(120, 280, ["朋友齐了，", "开一局！"], 44, C["white"], gap=63)
    b.star(375, 243, 2.2, "celebrate", -7)
    b.text(700, 223, "现在开玩", T["size.body"], C["sky.lip"], T["weight.title"])
    b.button(700, 244, 480, "选择游戏", "primary", "focus", M["button.height.large"])
    b.text(700, 360, "挑一个喜欢的游戏，开局后邀请朋友。", T["size.body"], C["muted"])
    b.button(700, 384, 480, "加入游戏", "secondary", "default", M["button.height.large"])
    b.text(700, 500, "找附近的游戏，或扫描朋友的邀请。", T["size.body"], C["muted"])
    b.button(56, 608, 576, "用户信息", "secondary", "default", M["button.height.small"])
    b.button(648, 608, 576, "设置", "secondary", "default", M["button.height.small"])
    b.raw("</g>")
    b.text(540, 1262, "电视首页：左侧星星角色，右侧稳定主操作；焦点与选中状态分离。", T["size.meta"], C["muted"], T["weight.body"])
    return b


def feedback() -> Board:
    b = Board(1600, 900, f'星星大作战 v{TOKENS["version"]} 反馈与无障碍')
    b.header("04", "反馈与无障碍", "触感、动效、音效、按下过程与可关闭选项")

    b.panel(32, 124, 820, 360, "触感反馈", "ms、amplitude、用途均读取 tokens.haptic")
    headers = (("类型", 58), ("时长", 188), ("幅度", 286), ("用途", 392))
    for label, x in headers:
        b.text(x, 210, label, T["size.meta"], C["muted"], T["weight.label"])
    haptic_labels = {"tap": "轻触", "select": "选择", "confirm": "确认", "warn": "警告"}
    for i, key in enumerate(("tap", "select", "confirm", "warn")):
        item = TOKENS["haptic"][key]
        y = 248 + i * 48
        if i % 2 == 0:
            b.rect(50, y - 28, 784, 42, C["page"], M["radius.input"])
        b.text(58, y, f'{haptic_labels[key]} / {key}', T["size.meta"], C["ink"], T["weight.label"])
        b.text(188, y, f'{item["ms"]} ms', T["size.meta"], C["ink"])
        b.text(286, y, str(item["amplitude"]), T["size.meta"], C["ink"])
        b.text(392, y, item["use"], T["size.meta"], C["ink"])
    b.multiline(58, 446, ["规则：" + TOKENS["haptic"]["rules"][:31], TOKENS["haptic"]["rules"][31:]], 16, C["muted"], T["weight.body"], gap=24)

    b.panel(876, 124, 692, 360, "动效时长", "所有时长来自 motion_ms")
    motion_names = {"press": "按下", "release": "释放", "focus": "焦点", "page": "页面", "sheet": "弹层", "celebrate": "庆祝"}
    for i, (key, value) in enumerate(TOKENS["motion_ms"].items()):
        col, row = i % 2, i // 2
        x, y = 904 + col * 318, 214 + row * 78
        b.rect(x, y, 286, 58, C["sky.soft"], M["radius.input"])
        b.text(x + 18, y + 37, motion_names[key], T["size.meta"], C["ink"], T["weight.label"])
        b.text(x + 264, y + 37, f"{value} ms", T["size.meta"], C["sky"], T["weight.title"], "end")
    b.text(904, 458, f'焦点缩放 {TOKENS["focus_feedback"]["button_scale"]} · 卡片 {TOKENS["focus_feedback"]["card_scale"]} · 光环 {TOKENS["focus_feedback"]["halo_hz"]} Hz', 16, C["muted"])

    b.panel(32, 508, 512, 326, "音效映射")
    sound_map = [("move", "移动焦点"), ("confirm", "确认选择"), ("launch", "启动游戏"), ("back", "返回上一层"), ("welcome", "进入首页欢迎")]
    for i, (name, use) in enumerate(sound_map):
        y = 584 + i * 46
        b.use("i-sound", 58, y - 20, 0.9, C["sky"])
        b.text(92, y, name, T["size.meta"], C["ink"], T["weight.label"])
        b.text(206, y, use, T["size.meta"], C["muted"], T["weight.body"])

    b.panel(568, 508, 600, 326, "按下过程：3 帧")
    frame_xs = [594, 786, 978]
    labels = ["静止", "按下下沉", "回弹"]
    for i, (x, label) in enumerate(zip(frame_xs, labels)):
        b.text(x + 76, 584, label, T["size.meta"], C["ink"], T["weight.label"], "middle")
        state = "pressed" if i == 1 else "default"
        b.button(x, 612, 152, "确认", "primary", state, M["button.height.small"], T["size.meta"])
        b.text(x + 76, 706, (f'{TOKENS["motion_ms"]["press"]} ms' if i == 1 else f'{TOKENS["motion_ms"]["release"]} ms' if i == 2 else "lip 4"), 16, C["muted"], T["weight.body"], "middle")
    b.line(752, 638, 778, 638, C["sky"], M["stroke"])
    b.use("i-arrow", 752, 626, 1, C["sky"])
    b.line(944, 638, 970, 638, C["sky"], M["stroke"])
    b.use("i-arrow", 944, 626, 1, C["sky"])
    b.text(594, 774, "面整体下沉 4，厚底边消失；释放后短促回弹。", T["size.meta"], C["muted"])

    b.panel(1192, 508, 376, 326, "无障碍清单")
    checks = [
        f'文字对比度 ≥ {TOKENS["accessibility"]["text_contrast_min"]}:1',
        "可关闭音效",
        "可关闭震动",
        "减少动态效果",
    ]
    for i, label in enumerate(checks):
        y = 592 + i * 54
        b.circle(1224, y - 6, 15, C["success"])
        b.use("i-check", 1212, y - 18, 1, C["white"])
        b.text(1254, y, label, T["size.meta"], C["ink"], T["weight.label"])
    b.multiline(1216, 792, ["电视与桌面忽略触感；", "方向键移动焦点不震动。"], 15, C["muted"], T["weight.body"], gap=22)
    b.footer("FEEDBACK")
    return b


def write_boards() -> None:
    boards = [
        ("01-foundations.svg", foundations()),
        ("02-components.svg", components()),
        ("03-screens.svg", screens()),
        ("04-feedback.svg", feedback()),
    ]
    for filename, board in boards:
        (DESIGN / filename).write_text(board.svg(), encoding="utf-8")

    master_width = 1900
    total_height = sum(board.height for _, board in boards)
    chunks = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{master_width}" height="{total_height}" viewBox="0 0 {master_width} {total_height}" role="img" aria-label="{escape(TOKENS["brand"])} v{TOKENS["version"]} cheat sheet">',
        defs(),
        f'<rect width="{master_width}" height="{total_height}" fill="{C["page"]}"/>',
    ]
    y = 0
    for _, board in boards:
        x = (master_width - board.width) / 2
        chunks.append(f'<g transform="translate({x} {y})">')
        chunks.extend(board.parts)
        chunks.append("</g>")
        y += board.height
    chunks.append("</svg>\n")
    (DESIGN / "cheat-sheet.svg").write_text("\n".join(chunks), encoding="utf-8")
    print("Wrote:")
    for filename, _ in boards:
        print(DESIGN / filename)
    print(DESIGN / "cheat-sheet.svg")


if __name__ == "__main__":
    write_boards()
