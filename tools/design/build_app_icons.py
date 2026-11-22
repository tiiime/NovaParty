#!/usr/bin/env python3
"""Derive launcher variants from the selected NovaParty icon (assets/icon.svg)."""
import argparse
from copy import deepcopy
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)


def tag(name):
    return f'{{{NS}}}{name}'


def svg(size):
    return ET.Element(tag('svg'), width=str(size), height=str(size), viewBox='0 0 256 256')


def variants(master):
    background = master.find(f'.//*[@id="background"]')
    artwork = master.find(f'.//*[@id="artwork"]')
    mascot = artwork.find(f'.//*[@id="mascot"]')
    silhouette = mascot.find(f'.//*[@id="silhouette"]')

    # Android's layers are 108 dp; the center 66 dp is safe across launcher masks.
    # The complete design is scaled to the central 72 dp window; the mascot remains in the safe zone.
    foreground = svg(432)
    inset = dict(transform='translate(128 128) scale(0.666667) translate(-128 -128)')
    ET.SubElement(foreground, tag('g'), inset).append(deepcopy(artwork))
    back = svg(432)
    back.append(deepcopy(background))
    monochrome = svg(432)
    mask = ET.SubElement(ET.SubElement(monochrome, tag('g'), inset), tag('g'), transform=mascot.attrib['transform'])
    ET.SubElement(mask, tag('path'), d=silhouette.attrib['d'], fill='#FFFFFF')

    # Desktop does not apply the mobile corner mask. Leave padding for the Dock.
    mac = svg(1024)
    clip = ET.SubElement(ET.SubElement(mac, tag('defs')), tag('clipPath'), id='tile')
    ET.SubElement(clip, tag('rect'), x='12', y='12', width='232', height='232', rx='54')
    group = ET.SubElement(mac, tag('g'), {'clip-path': 'url(#tile)'})
    inner = ET.SubElement(group, tag('g'), transform='translate(12 12) scale(0.90625)')
    inner.append(deepcopy(background))
    inner.append(deepcopy(artwork))

    return {'android-background.svg': back, 'android-foreground.svg': foreground,
            'android-monochrome.svg': monochrome, 'desktop.svg': mac}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    directory = ROOT / 'assets/app-icons'
    if not args.check:
        directory.mkdir(parents=True, exist_ok=True)
    stale = []
    for filename, variant in variants(ET.parse(ROOT / 'assets/icon.svg').getroot()).items():
        for node in variant.iter():
            node.tail = None
        ET.indent(variant, space='  ')
        output = ET.tostring(variant, encoding='unicode') + '\n'
        path = directory / filename
        if args.check:
            if not path.is_file() or path.read_text(encoding='utf-8') != output:
                stale.append(filename)
        else:
            path.write_text(output, encoding='utf-8')
    if stale:
        raise SystemExit('Regenerate launcher variants: ' + ', '.join(stale))


if __name__ == '__main__':
    main()
