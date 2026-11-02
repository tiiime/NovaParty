#!/usr/bin/env python3
"""Real TCP Mod transfer, explicit consent, autojoin, immutable versions and restart."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import uuid
from client_ui_hot import shell
from integration import ROOT, free_port
from player_integration import wait_for
from debug_integration import submit
sys.path.insert(0,str(ROOT/'tools'))
from nvctl import push
from pack_mod import pack

def run():
 with tempfile.TemporaryDirectory(prefix='nv-lan-') as temp:
  temp=Path(temp)
  with shell(temp/'host') as (host,_),shell(temp/'guest') as (guest,_):
   source=temp/'mod';shutil.copytree(ROOT/'mods/gomoku',source)
   manifest=json.loads((source/'manifest.json').read_text())
   game='lan_probe_'+uuid.uuid4().hex[:12];manifest['id']=game;manifest['name']='局域网试验';manifest['version']='3.2.1'
   (source/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False))
   package=temp/'probe.zip';pack(source,package,hot=True)
   build=push(host,package);host.call('mods.activate',{'build':build['build']})
   port=free_port();host.room('room.create',{'game_id':game,'port':port,'nickname':'分享小星'})
   sid=host.call('game.snapshot')['game_session_id']
   target={'address':'127.0.0.1','port':port,'session_id':sid}
   guest.call('lan.inspect',target)
   wait_for(lambda:guest.call('lan.status')['confirmation'])
   assert game not in guest.call('ui.status')['game_ids']
   assert guest.call('lan.status')['received']==0
   assert not guest.call('game.snapshot')['in_room']
   guest.call('lan.cancel')
   assert not guest.call('lan.status')['confirmation']
   guest.call('lan.inspect',target)
   wait_for(lambda:guest.call('lan.status')['confirmation'])
   guest.call('lan.confirm_download')
   wait_for(lambda:guest.call('game.snapshot').get('in_room',False),timeout=15)
   state=guest.call('game.snapshot');assert state['game_id']==game and state['game_session_id']==sid
   result,_=submit(host,host.call('game.snapshot'),'first-move',{'type':'place','x':7,'y':7});assert result['accepted']
   wait_for(lambda:guest.call('game.snapshot')['revision']==1)
   guest.room('room.leave');host.room('room.leave')
   # A fresh host session allows the receiver to reuse the installed package without a prompt.
   host.room('room.create',{'game_id':game,'port':port})
   sid=host.call('game.snapshot')['game_session_id'];target['session_id']=sid
   guest.call('lan.inspect',target)
   wait_for(lambda:guest.call('game.snapshot').get('in_room',False))
   assert not guest.call('lan.status')['confirmation']
   guest.room('room.leave');host.room('room.leave')
  with shell(temp/'guest') as (guest,_):
   assert game in guest.call('ui.status')['game_ids']
 print('PASS LAN: no pre-consent download, cancel, SHA/namespace install, automatic join, real move, cached join and restart restore')

if __name__=='__main__':run()
