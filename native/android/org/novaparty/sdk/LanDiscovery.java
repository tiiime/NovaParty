package org.novaparty.sdk;
import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayDeque;
import java.util.Map;
import java.nio.charset.StandardCharsets;

/** Native NSD callbacks stay in Java; Godot polls bounded JSON events on its own thread. */
public final class LanDiscovery {
 public static String deviceName(Context context){
  try{String name=android.provider.Settings.Global.getString(context.getContentResolver(),"device_name");if(name!=null&&!name.trim().isEmpty())return name;}catch(Exception ignored){}
  return android.os.Build.MODEL;
 }
 private final NsdManager manager;
 private final ArrayDeque<JSONObject> events=new ArrayDeque<>();
 private final ArrayDeque<NsdServiceInfo> resolves=new ArrayDeque<>();
 private boolean browsing=false, registered=false, resolving=false;
 public LanDiscovery(Context context){manager=(NsdManager)context.getApplicationContext().getSystemService(Context.NSD_SERVICE);}
 private synchronized void emit(String type,String key,String address,int port,JSONObject txt){try{if(events.size()>=128)events.removeFirst();JSONObject e=new JSONObject();e.put("type",type);e.put("key",key);e.put("address",address);e.put("port",port);e.put("txt",txt);events.add(e);}catch(Exception ignored){}}
 private void error(int code){emit("error",String.valueOf(code),"",0,new JSONObject());}
 public synchronized String poll(){JSONArray list=new JSONArray();while(!events.isEmpty())list.put(events.removeFirst());return list.toString();}
 private NsdManager.DiscoveryListener discovery;
 private NsdManager.DiscoveryListener newDiscovery(){return new NsdManager.DiscoveryListener(){
  public void onDiscoveryStarted(String type){}
  public void onDiscoveryStopped(String type){}
  public void onStartDiscoveryFailed(String type,int code){error(code);}
  public void onStopDiscoveryFailed(String type,int code){error(code);}
  public void onServiceFound(NsdServiceInfo info){synchronized(LanDiscovery.this){if(discovery!=this)return;if(browsing&&resolves.size()<64)resolves.add(info);next();}}
  public void onServiceLost(NsdServiceInfo info){if(discovery!=this)return;emit("removed",info.getServiceName(),"",0,new JSONObject());}
 };}
 private NsdManager.RegistrationListener registration;
 private NsdManager.RegistrationListener newRegistration(){return new NsdManager.RegistrationListener(){
  public void onServiceRegistered(NsdServiceInfo info){}
  public void onRegistrationFailed(NsdServiceInfo info,int code){if(registration==this)registered=false;error(code);}
  public void onServiceUnregistered(NsdServiceInfo info){}
  public void onUnregistrationFailed(NsdServiceInfo info,int code){error(code);}
 };}
 private final NsdManager.ResolveListener resolver=new NsdManager.ResolveListener(){
  public void onResolveFailed(NsdServiceInfo info,int code){synchronized(LanDiscovery.this){resolving=false;next();}}
  public void onServiceResolved(NsdServiceInfo info){synchronized(LanDiscovery.this){resolving=false;if(browsing&&info.getHost()!=null){JSONObject txt=new JSONObject();try{for(Map.Entry<String,byte[]> e:info.getAttributes().entrySet())txt.put(e.getKey(),new String(e.getValue(),StandardCharsets.UTF_8));}catch(Exception ignored){}emit("found",info.getServiceName(),info.getHost().getHostAddress(),info.getPort(),txt);}next();}}
 };
 private synchronized void next(){if(browsing&&!resolving&&!resolves.isEmpty()){resolving=true;manager.resolveService(resolves.removeFirst(),resolver);}}
 public synchronized void browse(){stopBrowse();browsing=true;discovery=newDiscovery();try{manager.discoverServices("_novaparty._tcp.",NsdManager.PROTOCOL_DNS_SD,discovery);}catch(Exception e){browsing=false;error(-1);}}
 public synchronized void stopBrowse(){if(browsing){try{manager.stopServiceDiscovery(discovery);}catch(Exception ignored){}}browsing=false;resolves.clear();}
 public synchronized void advertise(int port,String metadata){stopAdvertise();try{JSONObject txt=new JSONObject(metadata);NsdServiceInfo info=new NsdServiceInfo();info.setServiceName("NovaParty-"+txt.getString("sid"));info.setServiceType("_novaparty._tcp.");info.setPort(port);java.util.Iterator<String> keys=txt.keys();while(keys.hasNext()){String key=keys.next();info.setAttribute(key,txt.getString(key));}registration=newRegistration();manager.registerService(info,NsdManager.PROTOCOL_DNS_SD,registration);registered=true;}catch(Exception e){error(-2);}}
 public synchronized void stopAdvertise(){if(registered){try{manager.unregisterService(registration);}catch(Exception ignored){}}registered=false;}
 public void close(){stopBrowse();stopAdvertise();}
}
