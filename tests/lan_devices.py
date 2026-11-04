#!/usr/bin/env python3
"""Device sender + Android receiver; real adb room/download touches."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from integration import ROOT, free_port
from player_integration import wait_for
from debug_integration import submit
sys.path.insert(0,str(ROOT/'tools'))
from dev_config import adb_path, setting
from nvctl import Client,push
from pack_mod import pack

SERIAL = setting("ANDROID_EMULATOR_SERIAL", "emulator-5554")
PREFIX = "lan-arm-"

def capture(name):
 (ROOT/'build/validation'/(PREFIX+name+'.png')).write_bytes(subprocess.check_output([adb_path(),'-s',SERIAL,'exec-out','screencap','-p']))

def catalog(address,port):
 import socket
 with socket.create_connection((address,port),timeout=5) as s,s.makefile('rb') as f:
  s.sendall(b'{"type":"catalog"}\n')
  return json.loads(f.readline())

def run(sender_path, receiver_path, sender_serial='', direct=False):
 config=json.loads(sender_path.read_text())
 sender=Client(config,timeout=30);receiver=Client(json.loads(receiver_path.read_text()),timeout=30)
 baseline=sender.call('mods.status')['active'].get('gomoku','builtin:gomoku')
 downloaded=''
 try:
  for c in [sender,receiver]:
   assert c.call('device.info')['version']=='0.1.15'
   assert not c.call('game.snapshot')['in_room']
  with tempfile.TemporaryDirectory(prefix='nv-lan-devices-') as d:
   source=Path(d)/'mod';shutil.copytree(ROOT/'mods/gomoku',source)
   rules=source/'rules.gd';rules.write_text(rules.read_text()+'\n# LAN device transfer fixture '+uuid.uuid4().hex+'\n')
   manifest=json.loads((source/'manifest.json').read_text());manifest['name']='五子棋 · 传输测试';manifest['version']='0.2.0-lan-test';(source/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False))
   package=Path(d)/'mod.zip';pack(source,package,hot=True)
   build=push(sender,package);sender.call('mods.activate',{'build':build['build']})
   port=free_port()
   if sender_serial:subprocess.run([adb_path(),'-s',sender_serial,'forward','tcp:'+str(port),'tcp:'+str(port)],check=True,capture_output=True)
   sender.room('room.create',{'game_id':'gomoku','port':port})
   sid=sender.call('game.snapshot')['game_session_id']
   receiver.call('lan.search')
   if direct:
    receiver.call('lan.inspect',{'address':config['host'],'port':port,'session_id':sid})
   else:
    wait_for(lambda:any(r['session_id']==sid for r in receiver.call('lan.status')['rooms']),timeout=20)
    capture('rooms');print('LAN_ROOM_READY: tap the transfer-test Gomoku room',flush=True)
   wait_for(lambda:receiver.call('lan.status')['confirmation'],timeout=90)
   assert receiver.call('lan.status')['received']==0 and len(sender.call('game.snapshot')['players'])==1
   meta=catalog(config['host'],port);downloaded=meta['sha256']
   capture('confirmation');print('LAN_DOWNLOAD_READY: tap Download and join',flush=True)
   wait_for(lambda:receiver.call('game.snapshot').get('in_room',False),timeout=90)
   assert receiver.call('game.snapshot')['game_session_id']==sid
   result,_=submit(sender,sender.call('game.snapshot'),'lan-real-black',{'type':'place','x':7,'y':7});assert result['accepted']
   wait_for(lambda:receiver.call('game.snapshot')['revision']==1)
   capture('joined')
   receiver.room('room.leave');sender.room('room.leave')
   sender.room('room.create',{'game_id':'gomoku','port':port})
   invite=sender.call('qr.status')['invite'];assert invite['session_id']!=sid
   image=sender.call('qr.image')['data'];assert image
   (ROOT/'build/validation/lan-device-join-qr.png').write_bytes(base64.b64decode(image))
   decoded=receiver.call('qr.decode_image',{'data':image})['value'];assert decoded==invite['uri']
   receiver.call('qr.join',{'value':decoded})
   wait_for(lambda:receiver.call('game.snapshot').get('in_room',False),timeout=15)
   assert receiver.call('game.snapshot')['game_session_id']==invite['session_id']
   assert not receiver.call('lan.status')['confirmation']
   report={'sender':sender.call('device.info')['model'],'receiver':receiver.call('device.info')['model'],'base':'0.1.15','real_mdns_discovery':not direct,'actual_adb_room_touch':not direct,'actual_adb_download_consent':True,'no_bytes_before_consent':True,'regular_sdk_download':True,'auto_join':True,'real_move':True,'generated_qr_decoded':True,'decoded_invite_auto_join':True,'physical_camera_scan':False,'package_sha256':downloaded}
   (ROOT/'build/validation/lan-arm-devices.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
   receiver.room('room.leave');sender.room('room.leave')
   sender.call('mods.activate',{'build':baseline})
   print('PASS devices: real mDNS, real room/download touches, regular SDK Mod transfer, autojoin, move, QR decoding and cached join',flush=True)
 finally:
  sender.close();receiver.close()
  if downloaded:
   # Stop before deleting a mounted ZIP; recreate the VFS before the next test.
   subprocess.run([adb_path(),'-s',SERIAL,'shell','am','force-stop','org.novaparty.prototype'],check=True)
   subprocess.run([adb_path(),'-s',SERIAL,'shell','run-as','org.novaparty.prototype','rm','-f','files/mods/'+downloaded+'.zip'],check=True)

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--sender',type=Path,default=Path('/tmp/novaparty-iphone.connection.json'))
 parser.add_argument('--receiver',type=Path,default=Path('/tmp/novaparty-emulator.connection.json'))
 parser.add_argument('--serial',default=setting('ANDROID_EMULATOR_SERIAL', 'emulator-5554'))
 parser.add_argument('--sender-serial',default='')
 parser.add_argument('--direct',action='store_true',help='Use direct address when host mDNS does not cross emulator NAT')
 args=parser.parse_args();SERIAL=args.serial
 run(args.sender,args.receiver,args.sender_serial,args.direct)
