#!/usr/bin/env python3
"""Untrusted transport bytes must not become installed/executed Mod code."""
import hashlib
import json
from pathlib import Path
import socket
import tempfile
import threading
from client_ui_hot import shell
from player_integration import wait_for

class Source:
 def __init__(self, payload, corrupt=False, oversize=False):
  self.payload=payload;self.reads=0;self.socket=socket.socket();self.socket.bind(('127.0.0.1',0));self.port=self.socket.getsockname()[1];self.socket.listen();self.done=False
  self.metadata={'type':'catalog','protocol':1,'session_id':'1'*32,'game_id':'invalid_lan_probe','name':'Invalid probe','version':'1','source_name':'Test','rules_fingerprint':'2'*64,'presentation_fingerprint':'3'*64,'sha256':'0'*64 if corrupt else hashlib.sha256(payload).hexdigest(),'size':16777217 if oversize else len(payload)}
  self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()
 def run(self):
  try:
   conn,_=self.socket.accept()
   with conn,conn.makefile('rb') as stream:
    while not self.done:
     line=stream.readline()
     if not line:break
     request=json.loads(line)
     if request['type']=='catalog':reply=self.metadata
     else:
      self.reads+=1
      import base64
      reply={'type':'package_chunk','offset':request['offset'],'data':base64.b64encode(self.payload).decode()}
     conn.sendall((json.dumps(reply)+'\n').encode())
  except OSError:pass
 def close(self):self.done=True;self.socket.close()

def run():
 with tempfile.TemporaryDirectory(prefix='nv-lan-failure-') as d:
  with shell(Path(d)) as (client,_):
   games=client.call('ui.status')['game_ids']
   for corrupt,oversize in [(True,False),(False,False),(False,True)]:
    source=Source(b'not-a-zip',corrupt,oversize)
    try:
     client.call('lan.inspect',{'address':'127.0.0.1','port':source.port})
     if oversize:
      wait_for(lambda:client.call('lan.status')['phase']=='failed')
     else:
      wait_for(lambda:client.call('lan.status')['confirmation'])
      assert source.reads==0
      client.call('lan.confirm_download')
      wait_for(lambda:client.call('lan.status')['phase']=='failed')
     assert client.call('ui.status')['game_ids']==games
     assert not client.call('game.snapshot')['in_room']
     assert not client.call('lan.status')['confirmation']
    finally:source.close()
 print('PASS invalid transport: oversized offer, corrupted SHA and non-ZIP never install or join; no package bytes fetched before consent')
if __name__=='__main__':run()
