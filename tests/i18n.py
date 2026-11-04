#!/usr/bin/env python3
"""Validate actual catalog key coverage and printf placeholders before export."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.compile(r'%(?:[0-9.\-+ ]*)([sdif])')


def catalog_pair(first, second):
    left, right = [json.loads(p.read_text()) for p in [first, second]]
    assert set(left) == set(right), (first, set(left) ^ set(right))
    for key, message in left.items():
        assert isinstance(message, str) and message and right[key], key
        assert FORMAT.findall(message) == FORMAT.findall(right[key]), key
    return set(left)


def main():
    platform = catalog_pair(ROOT / 'i18n/en.json', ROOT / 'i18n/zh_CN.json')
    used = set()
    for directory in ['app', 'sdk']:
        for path in (ROOT / directory).rglob('*.gd'):
            used.update(re.findall(r'\btr\("([A-Z_]+)"\)', path.read_text()))
    assert used <= platform, 'missing platform keys: ' + str(used - platform)
    for game in ['gomoku', 'hidden_cards', 'jump_rope', 'uno']:
        directory = ROOT / 'mods' / game
        keys = catalog_pair(directory / 'locale-en.json', directory / 'locale-zh.json')
        used = set(re.findall(r'_t\("([A-Za-z_]+)"\)', (directory / 'view.gd').read_text()))
        assert used <= keys, (game, used - keys)
        manifest = json.loads((directory / 'manifest.json').read_text())
        assert {'locale-en.json', 'locale-zh.json'} <= set(manifest['files'])
        assert not {'locale-en.json', 'locale-zh.json'} & set(manifest['rules_files'])
    print('PASS i18n: English/Chinese keys, placeholders, Mod packaging and presentation-only catalogs')


if __name__ == '__main__':
    main()
