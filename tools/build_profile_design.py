#!/usr/bin/env python3
"""Original shared avatar catalog and profile UI cheat sheet (SVG)."""
from pathlib import Path
import json
from build_uno_design import avatar
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/design/profile'; OUT.mkdir(exist_ok=True)
roles=[('bear','小熊'),('fox','狐狸'),('bunny','兔子'),('cat','小猫'),('dog','小狗'),('panda','熊猫')]
palettes=[('honey','蜂蜜','#DEA65C','#FFF0C9'),('berry','莓果','#D67EA8','#FFE4EF'),('mint','薄荷','#69B9A1','#E4FFF3'),('ocean','海盐','#7F9FD5','#E8F1FF')]
# The same catalog is decoded by SDK and the design sheet. No Mod dependency at runtime.
catalog={}
for role,_ in roles:
 for key,_,body,muzzle in palettes:
  a=avatar(role,80,88,112)
  if role=='cat': a=a[:-4]+'<path d="M-28 4L-44 -1M-28 12L-44 15M28 4L44 -1M28 12L44 15M-9 -29L-6 -19M0 -31V-19M9 -29L6 -19" fill="none" stroke="#40372E" stroke-width="2.5" stroke-linecap="round"/>'+a[-4:]
  for original in ['#DE9B54','#B59070','#ECE1CC','#D9BD8E','#90AFB8','#EEE8D9']:
   a=a.replace(original,body)
  for original in ['#F6EBD3','#F4E7CE']:a=a.replace(original,muzzle)
  catalog[role+'/'+key]=f'<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160">{a}</svg>'
path=ROOT/'assets/ui/characters.json';path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
s=[]
def rect(x,y,w,h,fill='#FFFFFF',r=24,stroke='none',sw=0):s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')
def text(x,y,value,size=24,fill='#133464',weight=500):s.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}">{value}</text>')
def animal(role,palette,x,y,size=100):s.append(f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="0 0 160 160">'+catalog[role+'/'+palette].split('>',1)[1].rsplit('</svg>',1)[0]+'</svg>')
rect(0,0,1600,1450,'#EDF4FF',0)
text(64,72,'星星大作战 · 用户角色',42,weight=800)
text(64,114,'简单配置，同一套身份走进所有游戏。24 种角色外观，主题色独立。',23,'#506786')
rect(64,155,460,590,'#2058E0',36);text(95,210,'首页入口',30,'#FFFFFF',700)
animal('fox','honey',220,240,150)
for y,label,fill in [(420,'选择游戏','#FFE34B'),(510,'加入游戏','#FFFFFF'),(600,'用户信息','#FFFFFF')]:
 rect(100,y,388,72,fill,36);text(215,y+47,label,28,weight=700)
rect(568,155,968,590);text(604,210,'用户信息',30,weight=800)
animal('fox','mint',600,235,150);text(780,275,'客厅电视',32,weight=700);text(780,312,'昵称留空时使用设备名称',20,'#506786')
rect(780,332,650,58,'#EDF4FF',18);text(804,370,'客厅电视',24)
text(604,420,'动物角色',22,weight=700)
for i,(r,n) in enumerate(roles):
 x=600+i*148;rect(x,438,126,106,'#F0F5FF',22,'#FF8A1C' if r=='fox' else 'none',4);animal(r,'mint',x+25,435,78);text(x+42,535,n,18)
text(604,582,'角色配色',22,weight=700)
for i,(key,name,color,_) in enumerate(palettes):
 x=750+i*157;rect(x,550,142,56,color,26,'#133464' if key=='mint' else 'none',4);text(x+42,587,name,19)
text(604,650,'主题色',22,weight=700)
for i,color in enumerate(['#2058E0','#AB6DE0','#E56A9D','#258C78','#DC7840','#A87D12']):rect(750+i*85,620,62,54,color,27,'#FF8A1C' if i==0 else 'none',4)
rect(1290,662,190,60,'#FFE34B',30);text(1350,701,'保存',25,weight=700)
text(64,806,'角色与配色 · 6 × 4',30,weight=800)
for j,(role,name) in enumerate(roles):
 x=64+j*248;rect(x,840,230,510);text(x+84,885,name,25,weight=700)
 for i,(key,label,color,_) in enumerate(palettes):
  y=908+i*102;animal(role,key,x+8,y-10,100);rect(x+116,y+20,94,40,color,20);text(x+135,y+47,label,18)
text(64,1398,'选中：勾选＋描边 ｜ 焦点：橙色光圈 ｜ 取消：不保存 ｜ 保存：返回首页并显示新头像',22,'#506786')
(OUT/'cheat-sheet.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1450" viewBox="0 0 1600 1450"><g font-family="Noto Sans SC, PingFang SC, sans-serif">'+''.join(s)+'</g></svg>')
print(OUT/'cheat-sheet.svg')
