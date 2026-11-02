#!/usr/bin/env python3
"""Build the Apple DNS-SD GDExtension using Xcode and the current Godot C ABI."""
from pathlib import Path
from dev_config import godot_path
import plistlib
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
GODOT = godot_path()
OUT = ROOT / 'addons/novaparty_bonjour'
OUT.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='nv-bonjour-') as temp:
    subprocess.run([GODOT, '--headless', '--dump-gdextension-interface'], cwd=temp, check=True, capture_output=True)
    for sdk, arch, target, name in [('macosx','arm64','arm64-apple-macos12','macos'),('iphonesimulator','x86_64','x86_64-apple-ios13-simulator','simulator'),('iphoneos','arm64','arm64-apple-ios13','ios')]:
        directory = OUT / name / 'NovaBonjour.framework'
        directory.mkdir(parents=True, exist_ok=True)
        sysroot = subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'], text=True).strip()
        subprocess.run(['xcrun','--sdk',sdk,'clang++','-std=c++17','-fobjc-arc','-dynamiclib','-target',target,'-isysroot',sysroot,'-I',temp,str(ROOT/'native/bonjour/bonjour.mm'),'-framework','Foundation','-framework','CoreImage','-framework','ImageIO','-framework','CoreGraphics',*(['-framework','UIKit','-framework','AVFoundation'] if sdk!='macosx' else []),'-install_name','@rpath/NovaBonjour.framework/NovaBonjour','-o',str(directory/'NovaBonjour')], check=True)
        (directory/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.novaparty.bonjour','CFBundleName':'NovaBonjour','CFBundleExecutable':'NovaBonjour','CFBundlePackageType':'FMWK','CFBundleVersion':'1','CFBundleShortVersionString':'1.0'}))
        subprocess.run(['codesign','--force','--sign','-',str(directory)], check=True, capture_output=True)
print('BONJOUR_BUILD_OK')
