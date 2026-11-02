package org.novaparty.sdk;
import android.app.Activity;
import android.app.Dialog;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.hardware.Camera;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.Button;
import android.widget.TextView;
import android.util.Base64;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.RGBLuminanceSource;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
import com.google.zxing.qrcode.QRCodeWriter;
import org.json.JSONObject;
import org.json.JSONArray;
import java.io.ByteArrayOutputStream;
import java.util.ArrayDeque;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Offline QR encoding/decoding. Camera frames are never stored or transmitted. */
@SuppressWarnings("deprecation")
public final class JoinQRCode {
 private final Activity activity;
 private Dialog dialog;
 private Camera camera;
 private final ArrayDeque<JSONObject> events=new ArrayDeque<>();
 private ExecutorService decoder;
 private final AtomicBoolean decoding=new AtomicBoolean(false);
 private volatile boolean active=false;
 public JoinQRCode(Activity activity){this.activity=activity;}
 public static String encode(String value){try{
  BitMatrix matrix=new QRCodeWriter().encode(value,BarcodeFormat.QR_CODE,384,384);
  int width=matrix.getWidth();int[] pixels=new int[width*width];for(int y=0;y<width;y++)for(int x=0;x<width;x++)pixels[y*width+x]=matrix.get(x,y)?Color.BLACK:Color.WHITE;
  Bitmap bitmap=Bitmap.createBitmap(pixels,width,width,Bitmap.Config.ARGB_8888);ByteArrayOutputStream stream=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.PNG,100,stream);bitmap.recycle();return Base64.encodeToString(stream.toByteArray(),Base64.NO_WRAP);
 }catch(Exception e){return "";}}
 public static String decodeImage(String encoded){try{
  byte[] bytes=Base64.decode(encoded,Base64.DEFAULT);BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,bounds);if(bounds.outWidth<1||bounds.outHeight<1||(long)bounds.outWidth*bounds.outHeight>16000000)return "";Bitmap bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap==null||bitmap.getWidth()*bitmap.getHeight()>16000000)return "";
  int width=bitmap.getWidth(),height=bitmap.getHeight();int[] pixels=new int[width*height];bitmap.getPixels(pixels,0,width,0,0,width,height);bitmap.recycle();return new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new RGBLuminanceSource(width,height,pixels)))).getText();
 }catch(Exception e){return "";}}
 private synchronized void emit(String type,String key,String value){try{JSONObject e=new JSONObject();e.put("type",type);e.put(key,value);events.add(e);}catch(Exception ignored){}}
 public synchronized String poll(){JSONArray out=new JSONArray();while(!events.isEmpty())out.put(events.removeFirst());return out.toString();}
 public boolean cameraAvailable(){return Camera.getNumberOfCameras()>0;}
 public void start(String title,String closeText){activity.runOnUiThread(()->{
  if(active)return;active=true;decoder=Executors.newSingleThreadExecutor();
  dialog=new Dialog(activity,android.R.style.Theme_Material_NoActionBar_Fullscreen);
  FrameLayout frame=new FrameLayout(activity);SurfaceView preview=new SurfaceView(activity);frame.addView(preview,new FrameLayout.LayoutParams(-1,-1));
  LinearLayout controls=new LinearLayout(activity);controls.setOrientation(LinearLayout.VERTICAL);controls.setPadding(24,32,24,24);controls.setBackgroundColor(0x99000000);
  TextView label=new TextView(activity);label.setText(title);label.setTextSize(24);label.setTextColor(Color.WHITE);controls.addView(label);
  Button close=new Button(activity);close.setText(closeText);controls.addView(close);close.setOnClickListener(v->{emit("qr_canceled","value","");close();});
  frame.addView(controls,new FrameLayout.LayoutParams(-1,-2));dialog.setContentView(frame);dialog.setOnCancelListener(d->{emit("qr_canceled","value","");close();});
  preview.getHolder().addCallback(new SurfaceHolder.Callback(){
   public void surfaceCreated(SurfaceHolder holder){try{
    if(!active)return;camera=Camera.open();Camera.Parameters p=camera.getParameters();Camera.Size best=null;for(Camera.Size s:p.getSupportedPreviewSizes())if(s.width<=1280&&(best==null||s.width>best.width))best=s;if(best!=null)p.setPreviewSize(best.width,best.height);
    if(p.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE))p.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_PICTURE);camera.setParameters(p);
    int rotation=activity.getWindowManager().getDefaultDisplay().getRotation()*90;Camera.CameraInfo info=new Camera.CameraInfo();Camera.getCameraInfo(0,info);camera.setDisplayOrientation((info.orientation-rotation+360)%360);camera.setPreviewDisplay(holder);
    camera.setPreviewCallback((data,source)->decodeFrame(data,source.getParameters().getPreviewSize()));camera.startPreview();emit("qr_opened","value","");
   }catch(Exception e){emit("qr_error","code","camera_unavailable");close();}}
   public void surfaceChanged(SurfaceHolder holder,int format,int w,int h){}
   public void surfaceDestroyed(SurfaceHolder holder){releaseCamera();}
  });dialog.show();
 });}
 private void decodeFrame(byte[] frame,Camera.Size size){if(!active||decoder==null||!decoding.compareAndSet(false,true))return;byte[] copy=frame.clone();decoder.execute(()->{try{
  String value=new QRCodeReader().decode(new BinaryBitmap(new HybridBinarizer(new PlanarYUVLuminanceSource(copy,size.width,size.height,0,0,size.width,size.height,false)))).getText();
  if(active){active=false;emit("qr_result","value",value);close();}
 }catch(Exception ignored){}finally{decoding.set(false);}});}
 private void releaseCamera(){if(camera!=null){try{camera.setPreviewCallback(null);camera.stopPreview();camera.release();}catch(Exception ignored){}camera=null;}}
 public void close(){active=false;activity.runOnUiThread(()->{releaseCamera();if(dialog!=null){dialog.setOnCancelListener(null);dialog.dismiss();dialog=null;}if(decoder!=null){decoder.shutdown();decoder=null;}});}
}
