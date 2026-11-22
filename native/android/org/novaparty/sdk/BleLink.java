package org.novaparty.sdk;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothStatusCodes;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanRecord;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * NovaParty Link over Bluetooth LE. The host is a GATT peripheral, guests are centrals; both
 * directions carry an opaque byte stream cut into (MTU - 3) chunks with one chunk in flight.
 * Godot drives it through exchange(json) and receives queued JSON events. See docs/bluetooth.md.
 */
public final class BleLink {
 private static final UUID SERVICE=UUID.fromString("6E6F7661-7061-7274-7900-000000000001");
 private static final UUID RX=UUID.fromString("6E6F7661-7061-7274-7900-000000000002");
 private static final UUID TX=UUID.fromString("6E6F7661-7061-7274-7900-000000000003");
 private static final UUID CCCD=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
 private static final int MAX_QUEUE=262144;
 private static final String TAG="NovaPartyBle";

 /** One direction of one link: pending bytes and the chunk currently on the air. */
 private static final class Lane {
  final ByteArrayOutputStream pending=new ByteArrayOutputStream();
  int mtu=23, flying=0;
  boolean open=false;
  // ATT caps one attribute value at 512 bytes even when the negotiated MTU is 517.
  byte[] take(){byte[] all=pending.toByteArray();int n=Math.min(all.length,Math.max(1,Math.min(512,mtu-3)));pending.reset();pending.write(all,n,all.length-n);return Arrays.copyOf(all,n);}
 }
 private static final class Guest {BluetoothDevice device;final Lane lane=new Lane();}
 private static final class Remote {BluetoothGatt gatt;BluetoothGattCharacteristic rx;final Lane lane=new Lane();int attempts=0;boolean closing=false;}

 private final Activity activity;
 private final Context context;
 private final BluetoothManager manager;
 private final BluetoothAdapter adapter;
 private final Handler handler=new Handler(Looper.getMainLooper());
 private final ArrayList<JSONObject> events=new ArrayList<>();
 private final Map<String,Guest> guests=new HashMap<>();
 private final Map<String,Integer> guestMtu=new HashMap<>();
 private final Map<String,Remote> remotes=new HashMap<>();
 private final Map<String,Long> seen=new HashMap<>();
 private BluetoothGattServer server;
 private BluetoothGattCharacteristic tx;
 private BluetoothLeAdvertiser advertiser;
 private String hostName="";
 private boolean advertising=false, scanning=false;
 private String lastState="", lastHostState="";

 public BleLink(Activity activity){
  this.activity=activity;this.context=activity.getApplicationContext();
  manager=(BluetoothManager)context.getSystemService(Context.BLUETOOTH_SERVICE);
  adapter=manager==null?null:manager.getAdapter();
 }

 // ---- Godot entry point ---------------------------------------------------------------
 public synchronized String exchange(String input){
  try{
   JSONObject command=new JSONObject(input==null||input.isEmpty()?"{}":input);
   String op=command.optString("op","");
   if(!op.isEmpty())handle(op,command);
  }catch(SecurityException e){android.util.Log.w(TAG,"permission",e);emitError("permission_denied");}
  catch(Exception e){android.util.Log.w(TAG,"exchange failed",e);emitError("bridge_failed:"+e.getClass().getSimpleName());}
  reportState(false);
  JSONArray list=new JSONArray();for(JSONObject event:events)list.put(event);events.clear();
  return list.toString();
 }

 private void handle(String op,JSONObject c) throws Exception{
  switch(op){
   case "ble_state":reportState(true);break;
   case "ble_permissions":requestPermissions(c.optBoolean("host",false));break;
   case "ble_host":hostStart(c.optString("name",""));break;
   case "ble_advertise":setAdvertising(c.optBoolean("enabled",true));break;
   case "ble_host_stop":hostStop();break;
   case "ble_scan":scanStart();break;
   case "ble_scan_stop":scanStop();break;
   case "ble_connect":connect(c.optString("key",""));break;
   case "ble_send":send(c.optString("link",""),Base64.decode(c.optString("data",""),Base64.DEFAULT));break;
   case "ble_close":close(c.optString("link",""));break;
   case "ble_shutdown":scanStop();hostStop();for(String key:new ArrayList<>(remotes.keySet()))close("c:"+key);break;
   default:break;
  }
 }

 private void emit(String type,String link,String field,Object value){
  try{JSONObject e=new JSONObject();e.put("type",type);if(link!=null)e.put("link",link);if(field!=null)e.put(field,value);events.add(e);}catch(Exception ignored){}
 }
 private void emitError(String code){emit("ble_error",null,"code",code);}

 // ---- permissions and state -----------------------------------------------------------
 private String[] permissions(boolean host){
  // Location is only needed for scans (the export doesn't declare neverForLocation).
  if(Build.VERSION.SDK_INT>=31)return host
   ? new String[]{Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_ADVERTISE}
   : new String[]{Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.ACCESS_FINE_LOCATION};
  return host?new String[0]:new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
 }
 private boolean granted(boolean host){
  for(String permission:permissions(host))if(context.checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)return false;
  return true;
 }
 private void requestPermissions(boolean host){
  if(adapter!=null&&!granted(host))activity.runOnUiThread(()->{
   try{
    List<String> request=new ArrayList<>();
    for(String permission:permissions(host))if(context.checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)request.add(permission);
    // Android 12+ ignores requests for precise location unless approximate is requested with it.
    if(Build.VERSION.SDK_INT>=31&&request.contains(Manifest.permission.ACCESS_FINE_LOCATION))request.add(Manifest.permission.ACCESS_COARSE_LOCATION);
    if(!request.isEmpty())activity.requestPermissions(request.toArray(new String[0]),4711);
   }catch(Exception ignored){}
  });
 }
 private String state(boolean host){
  if(adapter==null||!context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE))return "unsupported";
  if(!granted(host))return "unauthorized";
  try{return adapter.isEnabled()?"on":"off";}catch(SecurityException e){return "unauthorized";}
 }
 private void reportState(boolean force){
  String now=state(false), host=state(true);
  if(force||!now.equals(lastState)){lastState=now;emit("ble_state",null,"state",now);}
  if(force||!host.equals(lastHostState)){lastHostState=host;emit("ble_host_state",null,"state",host);}
 }
 private boolean ready(boolean host){String value=state(host);if(!"on".equals(value)){emitError("bluetooth_"+value);return false;}return true;}

 // ---- host (peripheral) ---------------------------------------------------------------
 private void hostStart(String name){
  hostStop();
  if(!ready(true))return;
  hostName=name;
  server=manager.openGattServer(context,serverCallback);
  if(server==null){emitError("gatt_server_unavailable");return;}
  BluetoothGattService service=new BluetoothGattService(SERVICE,BluetoothGattService.SERVICE_TYPE_PRIMARY);
  BluetoothGattCharacteristic rx=new BluetoothGattCharacteristic(RX,BluetoothGattCharacteristic.PROPERTY_WRITE,BluetoothGattCharacteristic.PERMISSION_WRITE);
  tx=new BluetoothGattCharacteristic(TX,BluetoothGattCharacteristic.PROPERTY_NOTIFY,0);
  tx.addDescriptor(new BluetoothGattDescriptor(CCCD,BluetoothGattDescriptor.PERMISSION_READ|BluetoothGattDescriptor.PERMISSION_WRITE));
  service.addCharacteristic(rx);service.addCharacteristic(tx);
  server.addService(service);
  setAdvertising(true);
 }
 private final AdvertiseCallback advertiseCallback=new AdvertiseCallback(){
  @Override public void onStartSuccess(AdvertiseSettings effective){synchronized(BleLink.this){if(advertising)emit("ble_advertising",null,null,null);}}
  @Override public void onStartFailure(int code){synchronized(BleLink.this){if(advertising){advertising=false;emitError("advertise_failed_"+code);}}}
 };
 private void setAdvertising(boolean enabled){
  if(server==null)return;
  if(advertising){try{if(advertiser!=null)advertiser.stopAdvertising(advertiseCallback);}catch(Exception ignored){}advertising=false;}
  if(!enabled)return;
  advertiser=adapter.getBluetoothLeAdvertiser();
  if(advertiser==null){emitError("advertise_failed_unsupported");return;}
  AdvertiseSettings settings=new AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH).setConnectable(true).setTimeout(0).build();
  AdvertiseData data=new AdvertiseData.Builder().setIncludeDeviceName(false).addServiceUuid(new ParcelUuid(SERVICE)).build();
  // Android cannot set a per-advertisement local name, so the room code travels as service data.
  AdvertiseData response=new AdvertiseData.Builder().setIncludeDeviceName(false).addServiceData(new ParcelUuid(SERVICE),hostName.getBytes(StandardCharsets.US_ASCII)).build();
  advertiser.startAdvertising(settings,data,response,advertiseCallback);
  advertising=true;
 }
 private void hostStop(){
  if(advertising){try{if(advertiser!=null)advertiser.stopAdvertising(advertiseCallback);}catch(Exception ignored){}}
  advertising=false;
  if(server!=null){
   for(Guest guest:guests.values()){try{server.cancelConnection(guest.device);}catch(Exception ignored){}}
   try{server.close();}catch(Exception ignored){}
  }
  guests.clear();guestMtu.clear();server=null;tx=null;
 }
 private final BluetoothGattServerCallback serverCallback=new BluetoothGattServerCallback(){
  @Override public void onConnectionStateChange(BluetoothDevice device,int status,int newState){synchronized(BleLink.this){
   if(newState!=BluetoothProfile.STATE_CONNECTED){guestMtu.remove(device.getAddress());if(guests.remove(device.getAddress())!=null)emit("ble_closed","p:"+device.getAddress(),"code","link_lost");}
  }}
  @Override public void onMtuChanged(BluetoothDevice device,int mtu){synchronized(BleLink.this){
   guestMtu.put(device.getAddress(),mtu);Guest guest=guests.get(device.getAddress());if(guest!=null)guest.lane.mtu=mtu;
  }}
  @Override public void onDescriptorWriteRequest(BluetoothDevice device,int requestId,BluetoothGattDescriptor descriptor,boolean prepared,boolean responseNeeded,int offset,byte[] value){synchronized(BleLink.this){
   if(server==null)return;
   boolean ok=CCCD.equals(descriptor.getUuid())&&!prepared&&value!=null&&value.length>=1;
   if(responseNeeded)try{server.sendResponse(device,requestId,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,offset,null);}catch(SecurityException ignored){}
   if(!ok)return;
   String address=device.getAddress();
   if((value[0]&1)!=0){
    if(!guests.containsKey(address)&&guests.size()<16){Guest guest=new Guest();guest.device=device;guest.lane.open=true;Integer mtu=guestMtu.get(address);if(mtu!=null)guest.lane.mtu=mtu;guests.put(address,guest);emit("ble_open","p:"+address,null,null);}
   }else if(guests.remove(address)!=null)emit("ble_closed","p:"+address,"code","unsubscribed");
  }}
  @Override public void onDescriptorReadRequest(BluetoothDevice device,int requestId,int offset,BluetoothGattDescriptor descriptor){synchronized(BleLink.this){
   if(server==null)return;
   byte[] value=guests.containsKey(device.getAddress())?BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE:BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE;
   try{server.sendResponse(device,requestId,BluetoothGatt.GATT_SUCCESS,0,value);}catch(SecurityException ignored){}
  }}
  @Override public void onCharacteristicWriteRequest(BluetoothDevice device,int requestId,BluetoothGattCharacteristic characteristic,boolean prepared,boolean responseNeeded,int offset,byte[] value){synchronized(BleLink.this){
   if(server==null)return;
   boolean ok=RX.equals(characteristic.getUuid())&&!prepared&&offset==0&&value!=null&&guests.containsKey(device.getAddress());
   if(ok)emit("ble_data","p:"+device.getAddress(),"data",Base64.encodeToString(value,Base64.NO_WRAP));
   if(responseNeeded)try{server.sendResponse(device,requestId,ok?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_WRITE_NOT_PERMITTED,offset,null);}catch(SecurityException ignored){}
  }}
  @Override public void onNotificationSent(BluetoothDevice device,int status){synchronized(BleLink.this){
   Guest guest=guests.get(device.getAddress());if(guest==null)return;
   if(status!=BluetoothGatt.GATT_SUCCESS){dropGuest(device.getAddress(),"notify_failed");return;}
   emit("ble_sent","p:"+device.getAddress(),"bytes",guest.lane.flying);guest.lane.flying=0;pumpGuest(device.getAddress());
  }}
 };
 private void dropGuest(String address,String code){
  Guest guest=guests.remove(address);if(guest==null)return;
  try{if(server!=null)server.cancelConnection(guest.device);}catch(Exception ignored){}
  emit("ble_closed","p:"+address,"code",code);
 }
 @SuppressWarnings("deprecation")
 private void pumpGuest(String address){
  Guest guest=guests.get(address);
  if(guest==null||server==null||tx==null||guest.lane.flying>0||guest.lane.pending.size()==0)return;
  byte[] chunk=guest.lane.take();boolean accepted;
  try{
   if(Build.VERSION.SDK_INT>=33)accepted=server.notifyCharacteristicChanged(guest.device,tx,false,chunk)==BluetoothStatusCodes.SUCCESS;
   else{tx.setValue(chunk);accepted=server.notifyCharacteristicChanged(guest.device,tx,false);}
  }catch(SecurityException|IllegalArgumentException e){android.util.Log.w(TAG,"notify",e);accepted=false;}
  if(accepted){guest.lane.flying=chunk.length;return;}
  // Stack busy: put the chunk back and try again shortly.
  byte[] rest=guest.lane.pending.toByteArray();guest.lane.pending.reset();guest.lane.pending.write(chunk,0,chunk.length);guest.lane.pending.write(rest,0,rest.length);
  handler.postDelayed(()->{synchronized(BleLink.this){pumpGuest(address);}},40);
 }

 // ---- guest (central) -----------------------------------------------------------------
 private final ScanCallback scanCallback=new ScanCallback(){
  @Override public void onScanResult(int type,ScanResult result){found(result);}
  @Override public void onBatchScanResults(List<ScanResult> results){for(ScanResult result:results)found(result);}
  @Override public void onScanFailed(int code){synchronized(BleLink.this){scanning=false;emitError("scan_failed_"+code);}}
 };
 private void found(ScanResult result){synchronized(this){
  ScanRecord record=result.getScanRecord();if(!scanning||record==null)return;
  List<ParcelUuid> uuids=record.getServiceUuids();
  byte[] data=record.getServiceData(new ParcelUuid(SERVICE));
  if(data==null&&(uuids==null||!uuids.contains(new ParcelUuid(SERVICE))))return;
  String name=record.getDeviceName();
  if(data!=null&&data.length>=2&&data.length<=20)name=new String(data,StandardCharsets.US_ASCII);
  // iOS may advertise our service UUID without the local name on space-limited packets.
  if(name==null||!name.startsWith("NP"))name="NP";
  String key=result.getDevice().getAddress();long now=System.currentTimeMillis();Long last=seen.get(key);
  if(last!=null&&now-last<1000)return;
  if(seen.size()>256)seen.clear();
  seen.put(key,now);
  try{JSONObject e=new JSONObject();e.put("type","ble_found");e.put("key",key);e.put("name",name);e.put("rssi",result.getRssi());events.add(e);}catch(Exception ignored){}
 }}
 private void scanStart(){
  scanStop();
  if(!ready(false))return;
  BluetoothLeScanner scanner=adapter.getBluetoothLeScanner();
  if(scanner==null){emitError("scan_unsupported");return;}
  ScanSettings settings=new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build();
  // No hardware filter: offloaded filters fail on some controllers (emulator, several TVs) and
  // then drop every result. found() filters by service UUID in software instead.
  scanner.startScan(Collections.<ScanFilter>emptyList(),settings,scanCallback);
  scanning=true;
 }
 private void scanStop(){
  if(scanning&&adapter!=null){try{BluetoothLeScanner scanner=adapter.getBluetoothLeScanner();if(scanner!=null)scanner.stopScan(scanCallback);}catch(Exception ignored){}}
  scanning=false;seen.clear();
 }
 private void connect(String key){
  if(!BluetoothAdapter.checkBluetoothAddress(key)||!ready(false)){emit("ble_closed","c:"+key,"code","connect_failed");return;}
  close("c:"+key);
  Remote remote=new Remote();remotes.put(key,remote);open(key,remote);
 }
 private void open(String key,Remote remote){
  remote.attempts++;
  try{remote.gatt=adapter.getRemoteDevice(key).connectGatt(context,false,new Callback(key,remote),BluetoothDevice.TRANSPORT_LE);}
  catch(SecurityException e){remote.gatt=null;}
  if(remote.gatt==null)fail(key,remote,"connect_failed");
 }
 private void fail(String key,Remote remote,String code){
  if(remotes.get(key)!=remote)return;
  try{if(remote.gatt!=null)remote.gatt.close();}catch(Exception ignored){}
  // Android often reports status 133 right after a previous link to the same host closed.
  if(!remote.lane.open&&!remote.closing&&remote.attempts<3){handler.postDelayed(()->{synchronized(BleLink.this){if(remotes.get(key)==remote)open(key,remote);}},450);return;}
  remotes.remove(key);emit("ble_closed","c:"+key,"code",code);
 }
 private final class Callback extends BluetoothGattCallback {
  final String key;final Remote remote;
  Callback(String key,Remote remote){this.key=key;this.remote=remote;}
  @Override public void onConnectionStateChange(BluetoothGatt gatt,int status,int newState){synchronized(BleLink.this){
   if(remotes.get(key)!=remote)return;
   if(status==BluetoothGatt.GATT_SUCCESS&&newState==BluetoothProfile.STATE_CONNECTED){try{if(!gatt.requestMtu(517))gatt.discoverServices();}catch(SecurityException e){fail(key,remote,"permission_denied");}}
   else fail(key,remote,remote.lane.open?"link_lost":"connect_failed");
  }}
  @Override public void onMtuChanged(BluetoothGatt gatt,int mtu,int status){synchronized(BleLink.this){
   if(remotes.get(key)!=remote)return;
   if(status==BluetoothGatt.GATT_SUCCESS)remote.lane.mtu=mtu;
   try{gatt.discoverServices();}catch(SecurityException e){fail(key,remote,"permission_denied");}
  }}
  @SuppressWarnings("deprecation")
  @Override public void onServicesDiscovered(BluetoothGatt gatt,int status){synchronized(BleLink.this){
   if(remotes.get(key)!=remote)return;
   BluetoothGattService service=status==BluetoothGatt.GATT_SUCCESS?gatt.getService(SERVICE):null;
   BluetoothGattCharacteristic notify=service==null?null:service.getCharacteristic(TX);
   remote.rx=service==null?null:service.getCharacteristic(RX);
   BluetoothGattDescriptor descriptor=notify==null?null:notify.getDescriptor(CCCD);
   if(remote.rx==null||descriptor==null){remote.attempts=3;try{gatt.disconnect();}catch(Exception ignored){}fail(key,remote,"service_missing");return;}
   try{
    gatt.setCharacteristicNotification(notify,true);
    boolean started;
    if(Build.VERSION.SDK_INT>=33)started=gatt.writeDescriptor(descriptor,BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)==BluetoothStatusCodes.SUCCESS;
    else{descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);started=gatt.writeDescriptor(descriptor);}
    if(!started){gatt.disconnect();fail(key,remote,"subscribe_failed");}
   }catch(SecurityException e){fail(key,remote,"permission_denied");}
  }}
  @Override public void onDescriptorWrite(BluetoothGatt gatt,BluetoothGattDescriptor descriptor,int status){synchronized(BleLink.this){
   if(remotes.get(key)!=remote||remote.lane.open)return;
   if(status!=BluetoothGatt.GATT_SUCCESS){try{gatt.disconnect();}catch(Exception ignored){}fail(key,remote,"subscribe_failed");return;}
   remote.lane.open=true;emit("ble_open","c:"+key,null,null);pumpRemote(key);
  }}
  @SuppressWarnings("deprecation")
  @Override public void onCharacteristicChanged(BluetoothGatt gatt,BluetoothGattCharacteristic characteristic){received(characteristic.getValue());}
  @Override public void onCharacteristicChanged(BluetoothGatt gatt,BluetoothGattCharacteristic characteristic,byte[] value){received(value);}
  private void received(byte[] value){synchronized(BleLink.this){
   if(remotes.get(key)==remote&&value!=null&&value.length>0)emit("ble_data","c:"+key,"data",Base64.encodeToString(value,Base64.NO_WRAP));
  }}
  @Override public void onCharacteristicWrite(BluetoothGatt gatt,BluetoothGattCharacteristic characteristic,int status){synchronized(BleLink.this){
   if(remotes.get(key)!=remote)return;
   if(status!=BluetoothGatt.GATT_SUCCESS){try{gatt.disconnect();}catch(Exception ignored){}return;}
   emit("ble_sent","c:"+key,"bytes",remote.lane.flying);remote.lane.flying=0;pumpRemote(key);
  }}
 }
 @SuppressWarnings("deprecation")
 private void pumpRemote(String key){
  Remote remote=remotes.get(key);
  if(remote==null||!remote.lane.open||remote.rx==null||remote.lane.flying>0||remote.lane.pending.size()==0)return;
  byte[] chunk=remote.lane.take();boolean accepted;
  try{
   if(Build.VERSION.SDK_INT>=33)accepted=remote.gatt.writeCharacteristic(remote.rx,chunk,BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)==BluetoothStatusCodes.SUCCESS;
   else{remote.rx.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);remote.rx.setValue(chunk);accepted=remote.gatt.writeCharacteristic(remote.rx);}
  }catch(SecurityException|IllegalArgumentException e){android.util.Log.w(TAG,"write",e);accepted=false;}
  if(accepted){remote.lane.flying=chunk.length;return;}
  byte[] rest=remote.lane.pending.toByteArray();remote.lane.pending.reset();remote.lane.pending.write(chunk,0,chunk.length);remote.lane.pending.write(rest,0,rest.length);
  handler.postDelayed(()->{synchronized(BleLink.this){pumpRemote(key);}},40);
 }

 // ---- shared --------------------------------------------------------------------------
 private void send(String link,byte[] data){
  if(data.length==0)return;
  Lane lane=null;
  if(link.startsWith("p:")){Guest guest=guests.get(link.substring(2));if(guest!=null)lane=guest.lane;}
  else if(link.startsWith("c:")){Remote remote=remotes.get(link.substring(2));if(remote!=null)lane=remote.lane;}
  if(lane==null)return;
  if(lane.pending.size()+data.length>MAX_QUEUE){close(link);emit("ble_closed",link,"code","queue_overflow");return;}
  lane.pending.write(data,0,data.length);
  if(link.startsWith("p:"))pumpGuest(link.substring(2));else pumpRemote(link.substring(2));
 }
 /** Local close: Godot already forgot the link, so no ble_closed event is queued. */
 private void close(String link){
  if(link.startsWith("p:")){
   Guest guest=guests.remove(link.substring(2));
   if(guest!=null&&server!=null){try{server.cancelConnection(guest.device);}catch(Exception ignored){}}
  }else if(link.startsWith("c:")){
   Remote remote=remotes.remove(link.substring(2));
   if(remote!=null){remote.closing=true;try{if(remote.gatt!=null){remote.gatt.disconnect();remote.gatt.close();}}catch(Exception ignored){}}
  }
 }
}
