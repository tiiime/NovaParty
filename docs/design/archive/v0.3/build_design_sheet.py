#!/usr/bin/env python3
"""Build v0.3 NovaParty vector design boards. Render with render_design_sheet.swift."""
import json
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'docs/design'
TOKENS = json.loads((ROOT / 'tokens.json').read_text())
C = TOKENS['color']
INK, MUTED, BLUE, YELLOW = (C[k] for k in ['text.primary', 'text.secondary', 'brand.sky', 'brand.star'])
PINK, MINT, CYAN = C['accent.pink'], C['accent.mint'], C['focus.halo']
FONT = 'Noto Sans SC, PingFang SC, Microsoft YaHei, sans-serif'
STAR = 'M49 10Q55 0 61 10L72 31 96 35Q108 37 99 47L82 64 86 88Q88 101 76 95L55 84 34 95Q22 101 24 88L28 64 11 47Q2 37 14 35L38 31Z'
DEFS = f'''<defs>
<linearGradient id="space" x2=".3" y2="1"><stop stop-color="#183CD4"/><stop offset="1" stop-color="#286DE9"/></linearGradient>
<radialGradient id="spot"><stop stop-color="#62BBFF" stop-opacity=".8"/><stop offset="1" stop-color="#62BBFF" stop-opacity="0"/></radialGradient>
<linearGradient id="gold" x2=".2" y2="1"><stop stop-color="#FFF86E"/><stop offset=".5" stop-color="{YELLOW}"/><stop offset="1" stop-color="#FFC536"/></linearGradient>
<linearGradient id="shell" x2=".15" y2="1"><stop stop-color="#FFFFFF"/><stop offset=".65" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E6F0FF"/></linearGradient>
<radialGradient id="pink"><stop offset="0" stop-color="#FFD4ED"/><stop offset=".45" stop-color="{PINK}"/><stop offset="1" stop-color="#D34E9D"/></radialGradient>
<radialGradient id="mint"><stop stop-color="#DAFFF7"/><stop offset=".4" stop-color="{MINT}"/><stop offset="1" stop-color="#16AAB8"/></radialGradient>
<linearGradient id="ribbon" x2="1" y2="1"><stop stop-color="#FF9CCF"/><stop offset="1" stop-color="#F953A2"/></linearGradient>
<path id="star-shape" d="{STAR}"/>
<g id="spark"><path d="M12 0Q12 10 24 12Q12 14 12 24Q11 14 0 12Q11 10 12 0Z" fill="currentColor"/></g>
<g id="search" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><circle cx="10" cy="10" r="7"/><path d="m15 15 7 7"/></g>
<g id="arrow" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18m-7-7 7 7-7 7"/></g>
<g id="check" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m4 12 5 5L21 5"/></g>
<g id="refresh" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 8a9 9 0 1 0 0 9M20 2v6h-6"/></g>
<g id="close" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="m5 5 14 14M19 5 5 19"/></g>
<g id="wifi" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M2 8q10-9 20 0M6 12q6-6 12 0m-8 4q2-2 4 0"/><circle cx="12" cy="20" r="1" fill="currentColor"/></g>
<g id="gear" fill="none" stroke="currentColor" stroke-width="2.3"><path d="m9 2 6 0 1 4 4 1 3 5-3 4-1 4-5 2-4-2-4-1-3-5 2-4 1-3 4-1Z"/><circle cx="12" cy="12" r="4"/></g>
<g id="cloud" fill="white"><path d="M0 40Q-2 17 22 18Q26-9 52 3Q69-8 82 15Q110 10 110 38Q110 53 92 53H17Q0 53 0 40Z"/></g>
</defs>'''


class Board:
    def __init__(self):
        self.parts = []

    def raw(self, markup):
        self.parts.append(markup)

    def rect(self, x, y, w, h, fill='white', r=28, stroke=None, sw=2):
        border = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{border}/>')

    def text(self, x, y, value, size=22, color=INK, weight=400, anchor='start'):
        self.raw(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{color}" text-anchor="{anchor}">{escape(str(value))}</text>')

    def lines(self, x, y, values, size=21, color=MUTED, gap=34):
        for i, value in enumerate(values):
            self.text(x, y+i*gap, value, size, color)

    def ellipse(self, x, y, rx, ry, fill, opacity=1):
        self.raw(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" opacity="{opacity}"/>')

    def use(self, name, x, y, scale=1, color=INK):
        self.raw(f'<use href="#{name}" transform="translate({x} {y}) scale({scale})" color="{color}"/>')

    def star(self, x, y, scale=1, mood='happy', angle=0):
        self.raw(f'<g transform="translate({x} {y}) scale({scale}) rotate({angle} 55 55)">')
        self.raw('<use href="#star-shape" transform="translate(0 4)" fill="#C98A14"/>')
        self.raw('<use href="#star-shape" fill="url(#gold)" stroke="#FFF7BA" stroke-width="1.8"/>')
        self.raw('<path d="M17 40 40 37 51 14" stroke="white" stroke-width="3.5" stroke-linecap="round" fill="none" opacity=".8"/>')
        if mood == 'celebrate':
            self.raw(f'<path d="m36 44 7 5-7 5m37-10-7 5 7 5" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>')
        else:
            self.ellipse(43 if mood == 'waiting' else 41, 49, 3, 4.5, INK)
            self.ellipse(69 if mood == 'waiting' else 68, 49, 3, 4.5, INK)
        if mood == 'waiting':
            self.raw(f'<path d="M49 64q7 5 13 0" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>')
        else:
            self.raw(f'<path d="M43 61 67 61Q57 83 43 61Z" fill="#E76898" stroke="{INK}" stroke-width="2"/>')
            self.raw('<path d="M49 70q7-3 12 0" fill="none" stroke="#FFC2D9" stroke-width="3"/>')
        self.ellipse(31, 60, 6, 3, '#F5A265', .7)
        self.ellipse(79, 60, 6, 3, '#F5A265', .7)
        self.raw('</g>')

    def pill(self, x, y, w, label, fill='white', color=INK, h=46, size=19):
        self.rect(x, y, w, h, fill, h/2)
        self.text(x+w/2, y+h/2+size*.35, label, size, color, 600, 'middle')

    def button(self, x, y, w, label, kind='primary', h=72, focused=False, subtitle=None, size=26, icon=None):
        disabled = kind == 'disabled'
        if focused:
            self.rect(x-11, y-11, w+22, h+22, CYAN, h/2+11)
            self.rect(x-6, y-6, w+12, h+12, BLUE, h/2+6)
        base = '#C5D4E9' if disabled else '#C58A0F' if kind in ['primary', 'pressed', 'busy'] else '#A6BEE5'
        face = '#E3EAF4' if disabled else C['button.primary.pressed'] if kind == 'pressed' else '#FFF1AD' if kind == 'busy' else 'url(#gold)' if kind == 'primary' else 'url(#shell)'
        self.rect(x, y+8, w, h, base, h/2)
        face_y = y+4 if kind == 'pressed' else y
        self.rect(x, face_y, w, h, face, h/2, '#FFFFFF' if not disabled else None, 3)
        if not disabled:
            self.raw(f'<path d="M{x+35} {face_y+9}H{x+w-35}" stroke="white" stroke-width="3" stroke-linecap="round" opacity=".65"/>')
        color = '#8396AD' if disabled else INK
        if icon:
            self.ellipse(x+59, y+h/2, 33, 33, '#FFFFFF', .6)
            self.use(icon, x+44, y+h/2-15, 1.25, BLUE)
        if subtitle:
            left = x+113 if icon else x+48
            self.text(left, y+h*.43, label, size, color, 700)
            self.text(left, y+h*.7, subtitle, max(19, int(size*.52)), color, 400)
            self.use('arrow', x+w-70, y+h/2-14, 1.4, color)
        else:
            self.text(x+w/2, y+h/2+size*.36, label, size, color, 700, 'middle')

    def panel(self, x, y, w, h, title, number):
        self.rect(x, y+7, w, h, '#D6E3FB', 32)
        self.rect(x, y, w, h, 'white', 32)
        self.rect(x+26, y+25, 47, 37, BLUE, 12)
        self.text(x+49, y+51, number, 19, 'white', 700, 'middle')
        self.text(x+89, y+53, title, 25, INK, 700)

    def confetti(self, points):
        for i, (x, y, angle, color) in enumerate(points):
            if i % 3 == 0:
                self.raw(f'<g transform="translate({x} {y}) rotate({angle})"><use href="#spark" color="{color}"/></g>')
            else:
                self.raw(f'<rect x="{x}" y="{y}" width="10" height="22" rx="4" fill="{color}" transform="rotate({angle} {x} {y})"/>')

    def sky(self, w=1920, h=1080):
        self.rect(0, 0, w, h, 'url(#space)', 0)
        self.ellipse(w*.28, h*.46, w*.42, h*.7, 'url(#spot)')
        self.raw(f'<path d="M0 {h*.87}Q{w*.25} {h*.80} {w*.52} {h*.9}Q{w*.78} {h*.97} {w} {h*.84}V{h}H0Z" fill="#E9F3FF"/>')

    def header(self, title, sub, number):
        self.rect(0, 0, 1920, 1440, '#EEF4FF', 0)
        self.rect(0, 0, 1920, 240, 'url(#space)', 0)
        self.text(64, 95, title, 44, 'white', 700)
        self.text(64, 147, sub, 23, 'white')
        self.pill(1515, 60, 340, '星星派对 · v0.3 / '+number, '#FFFFFF', BLUE)
        self.confetti([(1420, 66, 20, YELLOW), (1810, 154, 24, PINK), (1372, 179, -30, CYAN)])

    def footer(self, label):
        self.text(64, 1403, '星星大作战 · v0.3 星际派对 · SVG 设计提案 / 尚未应用到客户端', 18, MUTED)
        self.text(1856, 1403, label, 18, MUTED, 500, 'end')

    def svg(self, width=1920, height=1440, title='星星大作战 · 星际派对'):
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="{escape(title)}">\n{DEFS}\n<g font-family="{FONT}">\n'+ '\n'.join(self.parts)+'</g></svg>\n'


def lobby():
    b = Board()
    b.sky()
    # Peripheral color and a single stage, leaving the action area unobstructed.
    b.confetti([(100, 290, 20, CYAN), (830, 210, -25, PINK), (782, 793, 24, YELLOW), (1828, 812, -20, PINK), (1690, 204, 25, CYAN), (108, 720, -25, YELLOW), (895, 95, 10, 'white'), (1540, 124, -25, YELLOW), (1840, 342, 25, MINT)])
    b.ellipse(1690, 130, 45, 45, 'url(#pink)')
    b.ellipse(136, 490, 33, 33, 'url(#mint)')
    b.use('cloud', 1390, 210, 1.5, 'white')
    b.text(128, 148, '星星大作战', 80, '#1037AB', 700)
    b.text(128, 140, '星星大作战', 80, 'white', 700)
    b.text(133, 205, '朋友到齐，快乐起飞！', 29, 'white', 500)
    b.ellipse(505, 847, 283, 56, '#133BA3', .25)
    b.ellipse(505, 830, 280, 49, '#BFE5FF')
    b.ellipse(505, 815, 280, 46, 'white')
    b.ellipse(515, 812, 126, 14, '#8DABDB', .35)
    b.raw('<ellipse cx="510" cy="549" rx="320" ry="235" fill="none" stroke="#93E6FF" stroke-width="3" opacity=".5" transform="rotate(-18 510 549)"/>')
    b.star(274, 326, 4.25, 'happy', -9)
    b.star(730, 407, .88, 'celebrate', 13)
    b.star(157, 304, .65, 'waiting', -18)
    b.pill(277, 281, 383, '今天的快乐，现在开场！', 'white', INK, 58, 23)
    b.use('spark', 777, 610, 1.6, YELLOW)
    b.button(1000, 375, 742, '开始游戏', 'primary', 162, True, '创建房间，选个游戏', 46, 'arrow')
    b.button(1000, 592, 742, '加入游戏', 'secondary', 142, False, '找到朋友开的房间', 42, 'search')
    b.pill(120, 963, 241, '★  小星', 'white', INK, 58, 24)
    b.pill(1575, 963, 224, '设置', 'white', INK, 58, 24)
    b.use('gear', 1612, 980, 1, BLUE)
    b.text(1050, 914, '方向键选择 · 确认进入', 26, 'white', 500)
    return b


def foundations():
    b = Board()
    b.header('01 / 让开局像一场小派对', '饱和蓝天空 · 亮黄主角 · 白色玩具外壳 · 一次短促的庆祝', '01')
    b.panel(64, 280, 1056, 420, '颜色要有主次，热闹集中在视觉主角', '01')
    palette=[('舞台蓝', BLUE), ('星光黄', YELLOW), ('玩具白', '#FFFFFF'), ('糖果粉', PINK), ('薄荷青', MINT), ('深海字', INK)]
    for i,(name,col) in enumerate(palette):
        x=94+i*168
        b.rect(x, 387, 143, 118, col, 27, '#E1E8F4' if col=='#FFFFFF' else None)
        b.text(x, 545, name, 22, INK, 600)
        b.text(x, 579, col, 20, MUTED)
    b.lines(94, 637, ['蓝色承载空间；黄色锁定主操作；粉 / 青仅做小面积庆祝点缀。'], 22)
    b.panel(1144, 280, 712, 420, '星星像一个充气玩具', '02')
    for i,(mood,label,angle) in enumerate([('happy','欢迎',-8),('waiting','等待',3),('celebrate','庆祝',8)]):
        b.star(1190+i*210, 383, 1.45, mood, angle)
        b.text(1270+i*210, 592, label, 23, INK, 600, 'middle')
    b.text(1176, 648, '柔和体积 / 顶部高光 / 表情简单 / 轮廓清楚', 21, MUTED)
    b.panel(64, 734, 600, 510, '材质与形状', '03')
    b.button(99, 850, 530, '开始游戏', 'primary', 90)
    b.lines(99, 1000, ['胶囊外形 + 8 单位下沿，按压下沉 4。', '高光是一小段亮边，不铺满反光纹理。', '卡片 R28；面板 R32；按钮大圆角。', '白色表面配冷蓝底边，形成轻盈厚度。'], 22, gap=47)
    b.panel(688, 734, 600, 510, '文字与空间', '04')
    b.text(722, 866, '今晚，一起开局！', 35, INK, 700)
    b.text(722, 920, '只看一眼，就知道该点哪里。', 25, INK)
    b.lines(722, 1000, ['沿用 Noto Sans SC，标题 600–700。', '手机正文 17 / 26；电视 24 / 34。', '间距 8 / 12 / 16 / 24 / 32 / 48。', '白字放稳定蓝底；小字不压在彩带上。'], 22, gap=47)
    b.panel(1312, 734, 544, 510, '天空轻变，喜庆不靠闪烁', '05')
    for i,(name,col) in enumerate([('晨','#234BE0'),('日','#183CD4'),('暮','#393FD2'),('夜','#2639BD')]):
        b.rect(1344+i*123, 852, 104, 87, col, 24)
        b.text(1396+i*123, 908, name, 26, 'white', 600, 'middle')
    b.lines(1344, 1000, ['按当地时间微调天空，控件颜色稳定。', '装饰静置在周边；不持续飞舞。', '开房成功 / 朋友到齐 / 胜利时小爆发。', '减少动态效果时切换为静态星光。'], 21, gap=47)
    b.rect(64, 1282, 1792, 68, '#DCE9FF', 24)
    b.text(94, 1326, '参考 Astro Bot 官方主视觉 / 预告里的玩具感与蓝白层次；角色、图形和布局为星星大作战重新设计。', 22, INK, 500)
    b.footer('FOUNDATIONS')
    return b


def components():
    b=Board()
    b.header('02 / 按下去，真的像启动快乐', '主按钮有分量 · 焦点有亮边 · 状态有解释 · 庆祝有节制', '02')
    b.panel(64, 280, 1080, 362, '按钮与即时反馈', '06')
    for x,y,w,lab,kind in [(98,385,300,'开始游戏','primary'),(447,385,300,'加入游戏','secondary'),(794,385,312,'按下状态','pressed'),(98,510,300,'正在创建…','busy'),(447,510,300,'等待选择游戏','disabled')]:
        b.button(x,y,w,lab,kind,72)
    b.lines(794, 539, ['按压 100–140ms', '文字不变位，布局不跳动'], 21)
    b.panel(1168, 280, 688, 362, '电视：焦点是一圈亮起的入口', '07')
    b.rect(1202,382,620,158,BLUE,30)
    b.button(1235,422,554,'开始游戏','primary',76,True)
    b.text(1204,588,'青色外环 + 稳定蓝色间隙；与选中、禁用分开。',21,MUTED)
    b.panel(64,678,856,398,'等待也要知道在等什么', '08')
    rows=[('正在搜索附近房间…','取消','#E6F0FF',BLUE,'search'),('等待朋友加入 · 1 / 2','离开房间','#FFF6CA',INK,'wifi'),('连接已断开','重连','#FFF0F6','#AB3558','refresh')]
    for i,(label,act,bg,col,ico) in enumerate(rows):
        y=786+i*83;b.rect(96,y,792,62,bg,22);b.use(ico,116,y+19,1,col);b.text(158,y+40,label,22,col,600);b.text(850,y+40,act,20,col,600,'end')
    b.panel(944,678,912,398,'房间像一张派对邀请卡', '09')
    b.rect(978,782,844,155,'#C6D9F6',30);b.rect(978,774,844,155,'url(#shell)',30,'#D2E5FF',2)
    b.ellipse(1047,850,40,40,BLUE);b.star(1013,814,.62,'happy',-10)
    b.text(1112,828,'小星的房间',28,INK,700);b.text(1112,874,'五子棋 · 1 / 2 人 · 可加入',22,MUTED)
    b.button(1645,807,147,'加入','primary',70)
    b.text(978,1009,'整张卡片一个焦点；游戏名 / 人数 / 可加入状态一眼看清。',21,MUTED)
    b.panel(64,1112,1080,235,'快乐的反馈，也要可控', '10')
    b.lines(96,1218,['普通焦点 / 面板：180–240ms；庆祝：450–650ms，一次即停。','彩带最多 12 片，仅在画面周边；音效可关闭，减少动态效果可选。','网络操作先显示进行中，最终确认后再庆祝；失败保留输入与重试。'],22,gap=41)
    b.panel(1168,1112,688,235,'一套清楚的圆头图标', '11')
    for i,name in enumerate(['search','arrow','check','refresh','close','wifi']):b.use(name,1205+i*103,1220,1.5,BLUE)
    b.text(1202,1300,'图标搭配短文字；装饰不能看起来像可点按钮。',21,MUTED)
    b.footer('COMPONENTS & FEEDBACK')
    return b


def phone(b,x,y,w=402,h=854,join=False):
    b.rect(x,y+8,w,h,'#BBD0F1',44)
    b.rect(x,y,w,h,'white',44)
    clip=f'phone-screen-{x}'
    b.raw(f'<defs><clipPath id="{clip}"><rect x="{x+10}" y="{y+10}" width="{w-20}" height="{h-20}" rx="36"/></clipPath></defs><g clip-path="url(#{clip})">')
    b.rect(x+10,y+10,w-20,h-20,'url(#space)',36)
    b.rect(x+w/2-60,y+20,120,20,INK,10)
    b.ellipse(x+w*.55,y+h*.36,w*.6,h*.32,'url(#spot)')
    # A light floor anchors the bottom controls and gives the screen depth.
    b.raw(f'<path d="M{x+10} {y+h-112}Q{x+w/2} {y+h-158} {x+w-10} {y+h-112}V{y+h-46}Q{x+w-10} {y+h-10} {x+w-46} {y+h-10}H{x+46}Q{x+10} {y+h-10} {x+10} {y+h-46}Z" fill="#E9F3FF"/>')
    if not join:
        b.text(x+35,y+113,'星星大作战',32,'white',700)
        b.text(x+36,y+151,'朋友到齐，快乐起飞！',19,'white')
        b.ellipse(x+w/2,y+431,126,28,'#AEDCFF')
        b.ellipse(x+w/2,y+420,126,25,'white')
        b.star(x+106,y+213,1.72,'happy',-10)
        b.confetti([(x+40,y+227,-20,PINK),(x+w-55,y+195,20,CYAN),(x+57,y+371,10,YELLOW)])
        b.button(x+34,y+490,w-68,'开始游戏','primary',76,False,size=26)
        b.button(x+34,y+593,w-68,'加入游戏','secondary',70,False,size=25)
        b.text(x+34,y+h-45,'小星',20,INK,600)
        b.text(x+w-34,y+h-45,'设置',20,INK,600,'end')
    else:
        b.text(x+30,y+113,'‹  加入游戏',30,'white',700)
        b.pill(x+30,y+151,w-60,'找到 1 个可加入房间','#153FAD','white',44,18)
        b.rect(x+28,y+229,w-56,155,'#ABC7EE',26)
        b.rect(x+28,y+221,w-56,155,'url(#shell)',26)
        b.text(x+48,y+271,'小星的房间',25,INK,700)
        b.text(x+48,y+312,'五子棋 · 1 / 2 人',20,MUTED)
        b.pill(x+48,y+331,94,'可加入','#E1FFF4','#087658',32,16)
        b.use('arrow',x+w-66,y+310,1.2,BLUE)
        b.star(x+142,y+447,1.03,'waiting',4)
        b.text(x+w/2,y+621,'选个房间，一起开玩。',22,'white',600,'middle')
        b.button(x+34,y+h-102,w-68,'重新搜索','secondary',65,False,size=23)

    b.raw('</g>')


def layouts(hero):
    b=Board()
    b.header('03 / 一打开，就想拉朋友来玩', '手机保留两步入口；电视把星星伙伴与主操作做成同一个舞台。', '03')
    phone(b,64,290)
    phone(b,494,290,join=True)
    b.raw('<defs><clipPath id="tv-preview"><rect x="932" y="290" width="924" height="519.75" rx="26"/></clipPath></defs>')
    b.raw('<g clip-path="url(#tv-preview)"><g transform="translate(932 290) scale(.48125)">'+''.join(hero.parts)+'</g></g>')
    b.text(936,866,'电视大厅：大场景、大按钮、清楚的焦点',25,INK,700)
    b.lines(936,917,['星星与舞台占左侧；开始 / 加入稳定放在右侧。','蓝色背景承载气氛，白色和黄色操作层保持清楚。','手机留安全区域，电视逻辑画布 1280 × 720。','图中为设计示意，房间自动搜索仍待实现。'],22,gap=41)
    b.panel(932,1114,924,237,'信息少，欢乐感来自形状与空间', '12')
    b.lines(964,1218,['首页：开始游戏 → 创建房间 / 选择游戏；加入游戏 → 搜索房间。','游戏内美术自由，统一状态、输入反馈、返回行为和电视焦点。','进入对局后收起大厅彩带，棋盘和手牌获得完整注意力。'],21,gap=41)
    b.text(70,1192,'手机大厅',25,INK,700);b.text(500,1192,'加入游戏 / 房间已找到',25,INK,700)
    b.lines(70,1244,['立体主角 + 两个主入口。','昵称、设置退到边缘。'],21)
    b.lines(500,1244,['有结果、无结果、搜索中分开展示。','重试不清空已有输入。'],21)
    b.footer('PHONE & TV')
    return b


def write():
    hero=lobby()
    boards=[('01-foundations',foundations()),('02-components',components()),('03-layouts',layouts(hero))]
    for name,board in boards:
        (ROOT/(name+'.svg')).write_text(board.svg())
    (ROOT/'04-party-lobby.svg').write_text(hero.svg(1920,1080,'星星大作战 v0.3 · 星际派对大厅'))
    master=Board()
    for i,(_,board) in enumerate(boards):
        master.raw(f'<g transform="translate(0 {i*1440})">'+''.join(board.parts)+'</g>')
    (ROOT/'cheat-sheet.svg').write_text(master.svg(1920,4320,'星星大作战 v0.3 · Design Cheat Sheet'))
    print('Wrote v0.3: foundations, components, layouts, party lobby and full cheat sheet')


if __name__=='__main__':
    write()
