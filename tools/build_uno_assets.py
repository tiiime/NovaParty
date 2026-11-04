#!/usr/bin/env python3
"""Export original text-free SVG art for runtime decoding (no Godot imports)."""
import json
import re
from pathlib import Path
from build_uno_design import svg, avatar, card, wood_bg, table
ROOT = Path(__file__).resolve().parents[1]
out = ROOT / 'mods/uno/art'
out.mkdir(exist_ok=True)
def save(name,w,h,body):
    source=svg(w,h,body,name)
    source=re.sub(r'<text\b.*?</text>', '', source, flags=re.S)
    (out/(name+'.svg.txt')).write_text(source)
for kind in ['bear','fox','panda','bunny','dog','cat']:
    save(kind,140,160,avatar(kind,70,90,108))
for color in ['red','yellow','green','blue','wild']:
    save(color,112,162,card(56,81,color,''))
save('back',112,162,card(56,81,back=True))
save('table-wide',1920,1080,wood_bg(1920,1080)+table(960,560,655,325))
save('table-phone',540,1100,wood_bg(540,1100)+table(270,430,222,172))
manifest=ROOT/'mods/uno/manifest.json'
data=json.loads(manifest.read_text())
data['files']=[p for p in data['files'] if not p.startswith('art/')]+['art/'+p.name for p in sorted(out.iterdir())]
manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
