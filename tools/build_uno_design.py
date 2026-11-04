#!/usr/bin/env python3
"""Build editable UNO UI specification boards; no runtime Mod assets are changed."""
from pathlib import Path
import html
import json
import math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'docs/design/uno'
TOKENS = json.loads((OUT/'tokens.json').read_text())
C = TOKENS['colors']


def text(x, y, value, size=20, fill=None, weight=500, anchor='start', **attrs):
    more = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill or C["ink"]}" font-weight="{weight}" text-anchor="{anchor}" {more}>{html.escape(str(value))}</text>'


def rect(x, y, w, h, fill, r=16, stroke='none', sw=0):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'


def pill(x, y, w, h, value, fill=None, color=None, size=22):
    return rect(x, y, w, h, fill or C['cream'], h/2) + text(x+w/2, y+h/2+size*.35, value, size, color, 700, 'middle')


def definitions():
    return '''<defs>
<linearGradient id="wood" x2="0" y2="1"><stop stop-color="#BE8960"/><stop offset=".45" stop-color="#88583E"/><stop offset="1" stop-color="#57392D"/></linearGradient>
<radialGradient id="felt"><stop stop-color="#C86458"/><stop offset="1" stop-color="#A53E3E"/></radialGradient>
<radialGradient id="room"><stop stop-color="#71503C"/><stop offset="1" stop-color="#342822"/></radialGradient>
<filter id="shadow" x="-35%" y="-30%" width="170%" height="180%"><feDropShadow dx="0" dy="9" stdDeviation="8" flood-color="#211914" flood-opacity=".30"/></filter>
<clipPath id="phoneClip"><rect width="390" height="844" rx="32"/></clipPath>
</defs>'''


def svg(w, h, content, title):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{html.escape(title)}"><title>{html.escape(title)}</title>{definitions()}<g font-family="Noto Sans SC, PingFang SC, sans-serif">{content}</g></svg>'''


def paw(x, y, size=30, fill=None):
    fill = fill or C['ink']
    return f'<g transform="translate({x} {y}) scale({size/40})" fill="{fill}"><ellipse cx="0" cy="8" rx="13" ry="10"/><ellipse cx="-14" cy="-5" rx="5" ry="7" transform="rotate(-30 -14 -5)"/><ellipse cx="-5" cy="-12" rx="5" ry="7"/><ellipse cx="6" cy="-12" rx="5" ry="7"/><ellipse cx="15" cy="-4" rx="5" ry="7" transform="rotate(30 15 -4)"/></g>'


def cue(color, x, y, scale=1, fill=None):
    ink = fill or C[color+'_ink']
    if color == 'red': body = '<circle r="5"/>'
    elif color == 'yellow': body = '<path d="M0 -7L6 0L0 7L-6 0Z"/>'
    elif color == 'green': body = '<path d="M0 -7L7 5L-7 5Z"/>'
    else: body = '<path d="M-7 -3Q-3 -8 1 -3T9 -3M-7 4Q-3 -1 1 4T9 4" fill="none" stroke="'+ink+'" stroke-width="3"/>'
    return f'<g transform="translate({x} {y}) scale({scale})" fill="{ink}">{body}</g>'


def card(x, y, color='red', rank='3', scale=1, rotation=0, back=False, selected=False, dim=False):
    fill = C['yellow'] if back else C.get(color, C['wild'])
    ink = C.get(color+'_ink', C['ink'])
    s = f'<g transform="translate({x} {y}) rotate({rotation}) scale({scale})">'
    if selected:
        s += rect(-56, -81, 112, 162, C['focus_outer'], 16) + rect(-53, -78, 106, 156, C['cream'], 13)
    s += '<g filter="url(#shadow)">' + rect(-50, -75, 100, 150, fill, 10, C['cream'], 4) + '</g>'
    if back:
        s += '<ellipse rx="34" ry="42" fill="#FFF3D8" opacity=".35"/>' + paw(0, 0, 45)
    else:
        s += '<ellipse rx="31" ry="56" transform="rotate(25)" fill="#FFF9E9"/>'
        if color == 'wild':
            for dx,dy,col in [(-15,-16,'red'),(15,-16,'yellow'),(-15,16,'blue'),(15,16,'green')]:
                s += rect(dx-12,dy-18,24,36,C[col],4, C['cream'],1)
            if rank: s += text(0, 15, rank, 32, C['ink'], 900, 'middle', stroke=C['cream'], stroke_width=2, paint_order='stroke fill')
        elif rank == 'skip':
            s += '<circle r="23" fill="none" stroke="'+ink+'" stroke-width="8"/><path d="M-17 17L17 -17" stroke="'+ink+'" stroke-width="8"/>'
        elif rank == 'reverse':
            s += f'<path d="M-20 -12H15L7 -20M20 12H-15L-7 20" fill="none" stroke="{ink}" stroke-width="8" stroke-linejoin="round" stroke-linecap="round"/>'
        else:
            s += text(0, 19, rank, 51 if len(rank)==1 else 38, ink, 900, 'middle')
        corner = '⊘' if rank == 'skip' else '↔' if rank == 'reverse' else rank or '◆'
        s += text(-38, -48, corner, 18, C['cream'], 900, stroke=C['ink'], stroke_width='.6', paint_order='stroke fill')
        s += f'<g transform="rotate(180)">{text(-38,-48,corner,18,C["cream"],900,stroke=C["ink"],stroke_width=".6",paint_order="stroke fill")}</g>'
        if color != 'wild': s += cue(color, 32, -54, .8, C['cream'])
    if dim: s += rect(-48,-73,96,146,'#302B29',9) .replace('/>', ' opacity=".22"/>')
    return s+'</g>'


def avatar(kind, x, y, size=100, active=False):
    s=f'<g transform="translate({x} {y}) scale({size/100})">'
    if active: s+='<circle r="57" fill="#FFD575" opacity=".18"/><circle r="51" fill="none" stroke="#FFF3D8" stroke-width="5"/>'
    s+='<ellipse cy="44" rx="38" ry="9" fill="#211914" opacity=".22"/>'
    face={'fox':'#DE9B54','bear':'#B59070','bunny':'#ECE1CC','panda':'#EEE8D9','dog':'#D9BD8E','cat':'#90AFB8'}[kind]
    if kind in ['fox','cat']:
        s+=f'<path d="M-35 -8L-34 -48L-9 -31M35 -8L34 -48L9 -31" fill="{face}" stroke="#654B3B" stroke-width="2"/><path d="M-29 -26L-29 -38L-18 -29M29 -26L29 -38L18 -29" fill="#DCAEA1"/>'
    elif kind=='bunny':
        s+='<ellipse cx="-20" cy="-40" rx="12" ry="33" fill="#ECE1CC"/><ellipse cx="20" cy="-40" rx="12" ry="33" fill="#ECE1CC"/><ellipse cx="-20" cy="-44" rx="5" ry="22" fill="#D7A99E"/><ellipse cx="20" cy="-44" rx="5" ry="22" fill="#D7A99E"/>'
    else:
        ear='#45403D' if kind=='panda' else '#77543C' if kind=='dog' else face
        s+=f'<ellipse cx="-34" cy="-26" rx="17" ry="{27 if kind=="dog" else 17}" fill="{ear}"/><ellipse cx="34" cy="-26" rx="17" ry="{27 if kind=="dog" else 17}" fill="{ear}"/>'
    s+=f'<ellipse cy="1" rx="41" ry="38" fill="{face}"/>'
    if kind=='fox':s+='<path d="M-38 3Q-12 -5 0 30Q12 -5 38 3Q32 38 0 39Q-32 38 -38 3" fill="#F6EBD3"/>'
    else:s+='<ellipse cy="16" rx="25" ry="19" fill="#F4E7CE"/>'
    if kind=='panda':s+='<ellipse cx="-16" cy="-3" rx="12" ry="15" fill="#45403D" transform="rotate(22 -16 -3)"/><ellipse cx="16" cy="-3" rx="12" ry="15" fill="#45403D" transform="rotate(-22 16 -3)"/>'
    s+='<ellipse cx="-15" cy="-5" rx="4" ry="6" fill="#292A29"/><ellipse cx="15" cy="-5" rx="4" ry="6" fill="#292A29"/><circle cx="-16" cy="-7" r="1.5" fill="#FFF"/><circle cx="14" cy="-7" r="1.5" fill="#FFF"/><ellipse cy="11" rx="6" ry="4" fill="#40372E"/><path d="M0 14V19Q-6 24 -11 19M0 19Q6 24 11 19" fill="none" stroke="#75594C" stroke-width="2.5" stroke-linecap="round"/>'
    return s+'</g>'


def seat(x,y,kind,name,count,active=False):
    s=avatar(kind,x,y,112,active)
    s+=pill(x-104,y+58,208,48,name,C['cream'],C['ink'],26)
    right = x > 960
    for i in range(min(3,count)):s+=card(x+(-130 if right else 88)+i*11,y+3-i*3,scale=.34,rotation=(-12-i*7) if right else (12+i*7),back=True)
    s+=pill(x+(-175 if right else 110),y+13,52,42,str(count),C['wood_dark'],C['cream'],28)
    if active:
        s+=f'<path d="M{x-14} {y+127}L{x+14} {y+127}L{x} {y+149}Z" fill="{C["turn"]}"/>'
    return s


def wood_bg(w,h):
    s=rect(0,0,w,h,'url(#room)',0)
    for y in range(100,h,190):s+=f'<path d="M0 {y}L{w} {y-45}" stroke="#B68B65" stroke-opacity=".065" stroke-width="3"/>'
    return s


def table(cx,cy,rx,ry):
    return f'<ellipse cx="{cx}" cy="{cy+20}" rx="{rx+20}" ry="{ry+14}" fill="#201B18" opacity=".35"/><ellipse cx="{cx}" cy="{cy}" rx="{rx+14}" ry="{ry+14}" fill="url(#wood)" stroke="#4A3029" stroke-width="6"/><ellipse cx="{cx}" cy="{cy-5}" rx="{rx}" ry="{ry}" fill="url(#felt)" stroke="#D49B6D" stroke-opacity=".45" stroke-width="3"/>'


def menu(x,y,size=58):
    s=rect(x-size/2,y-size/2,size,size,C['wood_dark'],size*.3)
    for dy in [-10,0,10]:s+=f'<path d="M{x-13} {y+dy}H{x+13}" stroke="{C["cream"]}" stroke-width="4" stroke-linecap="round"/>'
    return s


def tv():
    s=wood_bg(1920,1080)
    s+=text(96,100,'UNO',48,C['cream'],900)+text(224,81,'聚会叠加',20,C['muted'],700)+text(224,111,'第 1 局 · 公共牌桌',18,C['muted'])+menu(1792,84,60)
    s+=table(960,560,655,325)
    s+='<g opacity=".55"><path d="M720 560C720 370 1200 370 1200 540" fill="none" stroke="#EBC18B" stroke-width="7"/><path d="M1200 600C1200 770 720 770 720 600" fill="none" stroke="#EBC18B" stroke-width="7"/><path d="M1186 532L1214 532L1200 558ZM706 608L734 608L720 581Z" fill="#EBC18B"/></g>'
    for i in range(3):s+=card(835+i*4,530-i*3,scale=1.15,rotation=-9,back=True)
    s+=pill(768,645,150,42,'牌堆 42',C['wood_dark'],C['cream'],22)
    s+=card(1080,536,'yellow','3',1.52,12)
    s+=pill(994,709,172,44,'◆ 黄色',C['cream'],C['yellow_ink'],24)
    items=[(425,210,'bear','小熊',7,False),(1495,210,'fox','小狐',4,True),(1690,535,'panda','团子',6,False),(1495,850,'bunny','阿兔',3,False),(425,850,'dog','豆豆',5,False),(230,535,'cat','小喵',7,False)]
    for args in items:s+=seat(*args)
    s+=pill(1360,110,270,50,'轮到小狐出牌',C['cream'],C['ink'],27)
    (OUT/'uno-tv-table.svg').write_text(svg(1920,1080,s,'UNO television public table — original animal avatars and private card backs'))


def phone_face(variant='normal'):
    s=rect(0,0,390,844,C['background'],32)+wood_bg(390,844)
    s+=text(22,44,'UNO',28,C['cream'],900)+menu(350,30,38)
    opponents=[(50,135,'bear','小熊','7'),(122,105,'fox','小狐','4'),(195,90,'panda','团子','6'),(268,105,'bunny','阿兔','3'),(340,135,'dog','豆豆','5')]
    for x,y,k,n,c in opponents:
        s+=avatar(k,x,y,44)+pill(x-35,y+32,70,26,n,C['wood_dark'],C['cream'],14)+pill(x+8,y-7,30,26,c,C['cream'],C['ink'],16)
    s+=table(195,332,165,124)
    s+='<g opacity=".45" fill="#EBC18B" stroke="#EBC18B" stroke-width="3"><path d="M98 325C98 250 292 250 292 320M292 350C292 420 98 420 98 355" fill="none"/><path d="M287 316L297 316L292 326ZM93 359L103 359L98 349Z" stroke="none"/></g>'
    s+=pill(122,210,146,32,'轮到你了',C['cream'],C['ink'],18)
    for i in range(3):s+=card(145+i*2,329-i*2,scale=.56,rotation=-8,back=True)
    s+=text(141,400,'摸 1 张',15,C['cream'],700,'middle')
    s+=card(244,329,'yellow','3',.72,10)
    s+=pill(154,461,82,28,'◆ 黄色',C['cream'],C['yellow_ink'],14)
    if variant=='normal':
        ranks=[('red','2'),('blue','7'),('green','0'),('yellow','3'),('yellow','8'),('wild','+4'),('red','skip')]
        for i in [0,1,2,4,5,6,3]:
            col,rank=ranks[i]
            dx=i-3;selected=i==3
            x=[64,100,136,172,254,290,326][i]
            s+=card(x,680+abs(dx)*7-(22 if selected else 0),col,rank,.7844 if selected else .74,dx*4,selected=selected,dim=(i in [0,1,2,6]))
        s+=pill(126,537,92,30,'再点出牌',C['cream'],C['ink'],15)
        s+=avatar('cat',33,796,42)+text(67,796,'你 · 7 张',16,C['cream'],700)
        s+=text(368,819,'1 / 1',12,C['muted'],500,'end')
    else:
        s+=card(138,700,'red','0',1.1,-8)+card(254,667,'wild','+4',1.15,8,selected=True)
        s+=avatar('cat',33,796,42)+text(67,796,'你 · 2 张',16,C['cream'],700)
        s+=rect(0,0,390,844,'#241F1C',32).replace('/>',' opacity=".48"/>')
        s+=rect(48,264,294,267,C['cream'],24)+text(195,304,'选一种颜色',22,C['ink'],800,'middle')
        for x,y,col,label in [(76,325,'red','红色'),(202,325,'yellow','黄色'),(76,419,'green','绿色'),(202,419,'blue','蓝色')]:
            s+=rect(x,y,112,78,C[col],16)+cue(col,x+23,y+24,1,C[col+'_ink'])+text(x+56,y+57,label,19,C['ink'] if col in ['yellow','green'] else C['cream'],800,'middle')
    s+='<rect x="145" y="829" width="100" height="4" rx="2" fill="#D4BEA5"/>'
    return '<g clip-path="url(#phoneClip)">'+s+'</g>'


def mobile():
    s=rect(0,0,1200,1100,'#F5EFDF',0)
    s+=text(64,64,'手机 · 手牌优先',34,C['ink'],900)+text(64,102,'同一张桌面，自己的牌放在拇指操作区。',19,'#786759')
    for x,variant,label in [(95,'normal','选择出牌'),(705,'wild','万用牌选色')]:
        s+=f'<g transform="translate({x} 151)">'+rect(-7,-7,404,858,C['wood_dark'],39)+phone_face(variant)+'</g>'
        s+=text(x+195,1060,label,22,C['ink'],800,'middle')
    (OUT/'uno-mobile-hand.svg').write_text(svg(1200,1100,s,'UNO mobile hand selection and four-color picker'))


def components():
    s=rect(0,0,1600,1430,'#F5EFDF',0)
    s+=text(64,65,'UNO · 玩具牌桌',40,C['ink'],900)+text(64,106,'暖木、红绒、彩色牌；界面退后，让牌和玩家成为主角。',22,'#786759')
    s+=pill(1290,40,246,44,'UI 规范 v0.1 · 设计稿',C['wood_dark'],C['cream'],18)
    s+=text(64,174,'01  色彩与材质',25,C['ink'],800)
    colors=[('background','背景木色'),('wood','暖木边缘'),('felt','红色绒布'),('cream','奶油白'),('red','红'),('yellow','黄'),('green','绿'),('blue','蓝')]
    for i,(col,label) in enumerate(colors):
        x=64+i*187
        s+=rect(x,202,164,56,C[col],12)+text(x,287,label,17,C['ink'],700)+text(x,314,C[col],15,'#786759')
    s+=text(64,383,'02  牌面：2∶3，白色圆角边框，斜椭圆，大数字 / 大符号',25,C['ink'],800)
    for i,(col,rank,back) in enumerate([('red','3',False),('yellow','7',False),('green','skip',False),('blue','reverse',False),('red','+2',False),('wild','',False),('wild','+4',False),('yellow','',True)]):
        x=148+i*188
        s+=card(x,518,col,rank,1.10,0,back=back)
        labels=['数字牌','黄色用深色字','跳过','反转','罚摸 +2','万用选色','罚摸 +4','统一牌背']
        s+=text(x,643,labels[i],18,C['ink'],700,'middle')
    s+=text(64,709,'03  交互状态：可出、选中、等待各有含义',25,C['ink'],800)
    for x,state,label in [(134,'ready','可出：保持饱和'),(325,'selected','选中：抬升＋描边'),(516,'disabled','不可出：轻压暗')]:
        s+=card(x,823-(12 if state=='selected' else 0),'green','5',.84,0,selected=state=='selected',dim=state=='disabled')+text(x,918,label,16,C['ink'],700,'middle')
    s+=avatar('fox',755,806,86,True)+pill(684,862,142,38,'小狐 · 4 张',C['wood_dark'],C['cream'],19)
    s+='<path d="M744 907H766L755 925Z" fill="#D6A552"/>'
    s+=text(755,946,'当前玩家：亮环＋桌边指针',17,C['ink'],700,'middle')
    s+=pill(947,760,228,54,'轮到你了',C['cream'],C['ink'],24)
    s+=pill(947,835,228,54,'累计罚牌 +8',C['penalty'],C['cream'],22)
    s+=pill(1230,760,290,54,'玩家断线 · 已暂停',C['wood_dark'],C['cream'],21)
    s+=text(1230,849,'持续提示直到问题解除',17,'#786759')+text(947,932,'每次只突出一个当前任务。',19,C['ink'],700)
    s+='<circle cx="1260" cy="925" r="34" fill="#D94D42" stroke="#FFF3D8" stroke-width="3"/>'+text(1260,932,'UNO',20,C['cream'],900,'middle')+text(1310,932,'两张牌时才出现',17,'#786759')
    s+=text(64,1029,'04  收起杂项，保留必要提示',25,C['ink'],800)
    s+=rect(64,1056,454,236,'#E8DDC8',20)+text(90,1095,'菜单',22,C['ink'],800)
    for y,label in [(1140,'玩法规则'),(1191,'设置'),(1242,'退出游戏')]:s+=text(95,y,label,21,C['ink'])
    s+=rect(550,1056,454,236,C['wood_dark'],20)+text(578,1102,'小狐忘喊 UNO',24,C['cream'],800)+text(578,1150,'只在可抓牌窗口出现',19,C['muted'])+pill(578,1192,206,58,'抓牌 +2',C['cream'],C['ink'],23)
    s+=rect(1036,1056,500,236,C['cream'],20)+avatar('bunny',1100,1140,68)+text(1160,1121,'阿兔获胜',29,C['ink'],900)+text(1160,1160,'本局 +120 分',19,'#786759')+pill(1060,1201,224,58,'再来一局',C['red'],C['cream'],23)+pill(1300,1201,210,58,'退出',C['wood_dark'],C['cream'],23)
    s+=text(64,1364,'电视：围桌玩家＋牌堆＋弃牌。手机：同桌缩略＋自己的扇形手牌。对局不展示后台表格。',20,C['ink'],700)
    (OUT/'uno-components.svg').write_text(svg(1600,1430,s,'UNO UI visual specification: materials, cards, selection, player cue and contextual hints'))


if __name__=='__main__':
    components();tv();mobile()
    print('UNO design SVGs generated in docs/design/uno; runtime UI unchanged.')
