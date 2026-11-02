#!/usr/bin/env python3
"""Move the Android emulator's synthetic camera through its shipped gRPC API.
Requires the macOS curl HTTP/2 client, no Python packages. Start endpoint with:
  adb -s emulator-5554 emu grpc 8554
Schema: Android SDK emulator/lib/emulator_controller.proto (PhysicalModelValue).
"""
import argparse
import base64
from contextlib import contextmanager
import json
import os
import time
import uuid
from pathlib import Path
import re
import struct
import subprocess
import tempfile

AUTH_CONFIG = None

def rpc(port, method, payload):
    frame=b'\0'+struct.pack('>I',len(payload))+payload
    with tempfile.TemporaryDirectory(prefix='nv-camera-rpc-') as folder:
        headers=Path(folder)/'headers'
        result=subprocess.run(['curl',*(['--config',str(AUTH_CONFIG)] if AUTH_CONFIG else []),'--silent','--show-error','--http2-prior-knowledge','--max-time','8','-D',str(headers),'-H','content-type: application/grpc','-H','te: trailers','--data-binary','@-','http://127.0.0.1:'+str(port)+'/android.emulation.control.EmulatorController/'+method],input=frame,capture_output=True,check=True)
        text=headers.read_text()
        status=re.search(r'grpc-status:\s*(\d+)',text,re.I)
        if not status or status.group(1)!='0':raise RuntimeError(text)
        return result.stdout[5:]

def varint(data,offset):
    value=0;shift=0
    while offset<len(data):
        byte=data[offset];offset+=1;value|=(byte&127)<<shift
        if byte<128:return value,offset
        shift+=7
    raise ValueError('truncated protobuf')

def parameters(data):
    offset=0
    while offset<len(data):
        tag,offset=varint(data,offset)
        if tag&7==0:_,offset=varint(data,offset)
        elif tag&7==2:
            length,offset=varint(data,offset);value=data[offset:offset+length];offset+=length
            if tag>>3==3 and value[:1]==b'\x0a':
                size,start=varint(value,1)
                return struct.unpack('<'+'f'*(size//4),value[start:start+size])
        else:raise ValueError('unexpected protobuf field')
    return ()


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()

@contextmanager
def authorize(port):
    """Register a temporary testing-client key; preserve the emulator's JWT enforcement."""
    global AUTH_CONFIG
    running=Path.home()/'Library/Caches/TemporaryItems/avd/running'
    selected=None
    for path in running.glob('pid_*.ini'):
        fields=dict(line.split('=',1) for line in path.read_text().splitlines() if '=' in line)
        if fields.get('grpc.port')==str(port):selected=fields;break
    if selected is None:raise RuntimeError('Start the emulator gRPC endpoint first')
    name=selected.get('avd.name','')
    if not name.startswith('NovaParty_'):raise RuntimeError('Only NovaParty development AVDs are supported')
    directory=Path(selected['grpc.jwks'])
    if directory.stat().st_uid!=os.getuid():raise RuntimeError('Emulator must belong to this user')
    kid='novaparty-'+uuid.uuid4().hex
    public=directory/(kid+'.jwk')
    with tempfile.TemporaryDirectory(prefix='nv-camera-auth-') as folder:
        private=Path(folder)/'key.pem'
        subprocess.run(['openssl','ecparam','-name','prime256v1','-genkey','-noout','-out',str(private)],check=True,capture_output=True)
        private.chmod(0o600)
        der=subprocess.run(['openssl','ec','-in',str(private),'-pubout','-outform','DER'],capture_output=True,check=True).stdout
        assert der[-65]==4
        public.write_text(json.dumps({'keys':[{'kty':'EC','crv':'P-256','use':'sig','alg':'ES256','kid':kid,'x':b64(der[-64:-32]),'y':b64(der[-32:])}]}));public.chmod(0o600)
        header=b64(json.dumps({'alg':'ES256','kid':kid}).encode())
        now=int(time.time())
        claims=b64(json.dumps({'iss':'gradle-utp-emulator-control','iat':now-5,'exp':now+90,'aud':['/android.emulation.control.EmulatorController/setPhysicalModel','/android.emulation.control.EmulatorController/getPhysicalModel']}).encode())
        data=(header+'.'+claims).encode()
        signature=subprocess.run(['openssl','dgst','-sha256','-sign',str(private)],input=data,capture_output=True,check=True).stdout
        offset=2;assert signature[offset]==2
        length=signature[offset+1];r=signature[offset+2:offset+2+length];offset+=2+length;assert signature[offset]==2
        length=signature[offset+1];s=signature[offset+2:offset+2+length]
        token=header+'.'+claims+'.'+b64(r.lstrip(b'\0').rjust(32,b'\0')+s.lstrip(b'\0').rjust(32,b'\0'))
        config=Path(folder)/'curl.conf';config.write_text('header = "authorization: Bearer '+token+'"\n');config.chmod(0o600)
        AUTH_CONFIG=config
        try:
            for i in range(40):
                if kid in Path(selected['grpc.jwk_active']).read_text():break
                time.sleep(.1)
            yield
        finally:
            AUTH_CONFIG=None
            public.unlink(missing_ok=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=8554)
    parser.add_argument('--position',nargs=3,type=float)
    parser.add_argument('--rotation',nargs=3,type=float)
    args=parser.parse_args()
    with authorize(args.port):
      for target,values in [(0,args.position),(1,args.rotation)]:
          request=bytes([8,target])
          if values is not None:
              nested=b'\x0a\x0c'+struct.pack('<fff',*values)
              rpc(args.port,'setPhysicalModel',request+b'\x1a'+bytes([len(nested)])+nested+b'\x20\x01')
          print(('position' if target==0 else 'rotation'),parameters(rpc(args.port,'getPhysicalModel',request)))
