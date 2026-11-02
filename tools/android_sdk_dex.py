"""Add the ordinary SDK's Java bridge to the official non-Gradle Godot template."""
from pathlib import Path
import hashlib
import urllib.request
import subprocess
import tempfile
import zipfile

def include_sdk(apk, root, debug=True):
    from android_config import resolve
    config = resolve(debug)
    java = config.java / 'bin'
    build_tools, android = config.build_tools, config.android_jar
    sources=sorted((root/'native/android').rglob('*.java'))
    if debug:
        sources += sorted((root/'native/android_debug').rglob('*.java'))
    zxing=root/'build/deps/zxing-core-3.5.3.jar'
    zxing.parent.mkdir(parents=True,exist_ok=True)
    if not zxing.exists():
        urllib.request.urlretrieve('https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.3/core-3.5.3.jar',zxing)
    if hashlib.sha256(zxing.read_bytes()).hexdigest()!='8d8064c1636fdaef7189dd9055c7d59950a8940a12f2293956446ec3c109fd82':
        raise ValueError('ZXing dependency checksum mismatch')
    with tempfile.TemporaryDirectory(prefix='nv-sdk-dex-') as temp:
        temp=Path(temp);classes=temp/'classes';classes.mkdir();dex=temp/'dex';dex.mkdir()
        subprocess.run([str(java/'javac'),'-source','8','-target','8','-classpath',str(android)+':'+str(zxing),'-d',str(classes),*map(str,sources)],check=True,capture_output=True)
        jar=temp/'sdk.jar'
        subprocess.run([str(java/'jar'),'cf',str(jar),'-C',str(classes),'.'],check=True,capture_output=True)
        env=dict(__import__('os').environ, JAVA_HOME=str(java.parent),
                 NOVAPARTY_STORE_PASS=config.store_password, NOVAPARTY_KEY_PASS=config.key_password)
        subprocess.run([str(build_tools/'d8'),'--lib',str(android),'--min-api','21','--output',str(dex),str(jar),str(zxing)],check=True,capture_output=True,env=env)
        unsigned=temp/'unsigned.apk'
        with zipfile.ZipFile(apk) as original,zipfile.ZipFile(unsigned,'w') as out:
            names=original.namelist()
            for info in original.infolist():
                if not info.filename.startswith('META-INF/'):
                    out.writestr(info,original.read(info.filename))
            index=2
            while f'classes{index}.dex' in names:index+=1
            out.write(root/'native/licenses/ZXING-LICENSE.txt','assets/licenses/ZXING-LICENSE.txt')
            out.write(root/'native/licenses/ZXING-NOTICE.txt','assets/licenses/ZXING-NOTICE.txt')
            out.writestr(f'classes{index}.dex',(dex/'classes.dex').read_bytes(),compress_type=zipfile.ZIP_DEFLATED)
        aligned=temp/'aligned.apk'
        subprocess.run([str(build_tools/'zipalign'),'-P','16','-f','4',str(unsigned),str(aligned)],check=True,capture_output=True)
        subprocess.run([str(build_tools/'apksigner'),'sign','--ks',str(config.keystore),'--ks-key-alias',config.alias,'--ks-pass','env:NOVAPARTY_STORE_PASS','--key-pass','env:NOVAPARTY_KEY_PASS','--out',str(apk),str(aligned)],check=True,capture_output=True,env=env)
        subprocess.run([str(build_tools/'apksigner'),'verify',str(apk)],check=True,capture_output=True,env=env)
