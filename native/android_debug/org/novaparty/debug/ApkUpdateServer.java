package org.novaparty.debug;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Debug-only, authenticated self-update endpoint. Never included in Release DEX. */
public final class ApkUpdateServer {
    private static final long MAX_BYTES = 192L * 1024 * 1024;
    private final Activity activity;
    private final File directory, apk, record;
    private final AtomicBoolean uploading = new AtomicBoolean(), installing = new AtomicBoolean();
    private final Set<Socket> sockets = Collections.synchronizedSet(new HashSet<Socket>());
    private final ThreadPoolExecutor workers = new ThreadPoolExecutor(2, 2, 0, TimeUnit.SECONDS,
        new ArrayBlockingQueue<Runnable>(2));
    private JSONObject state = new JSONObject();
    private ServerSocket server;
    private String token;
    private BroadcastReceiver receiver;
    private volatile boolean closed;

    public ApkUpdateServer(Activity activity) {
        this.activity = activity;
        directory = new File(activity.getFilesDir(), "debug/apk");
        directory.mkdirs();
        apk = new File(directory, "update.apk");
        record = new File(directory, "status.json");
    }

    public String start(String address, int port, String secret) {
        if ((activity.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0)
            return "debug_required";
        try {
            token = secret;
            if (secret.length() != 64) return "invalid_token";
            if (record.isFile()) {
                try (InputStream input = new FileInputStream(record)) {
                    byte[] bytes = new byte[(int)Math.min(record.length(), 8192)];
                    int count = input.read(bytes);
                    state = new JSONObject(new String(bytes, 0, Math.max(0, count), StandardCharsets.UTF_8));
                }
            }
            new File(directory, "upload.part").delete();
            String previous = state.optString("state", "idle");
            if (Arrays.asList("installing", "awaiting_confirmation", "preparing_install").contains(previous)) {
                PackageInfo current = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
                if (current.lastUpdateTime > state.optLong("previous_update_time", Long.MAX_VALUE)) {
                    setState("installed", ""); apk.delete();
                } else setState("interrupted", "installation_interrupted");
            }
            if (previous.equals("receiving")) setState("interrupted", "upload_interrupted");
            server = new ServerSocket();
            server.bind(new InetSocketAddress(InetAddress.getByName(address), port), 4);
            new Thread(this::accept, "NovaParty APK HTTP").start();
            return "";
        } catch (Exception error) { close(); return "http_listen_failed"; }
    }

    private void accept() {
        while (!closed) {
            try {
                Socket socket = server.accept();
                socket.setSoTimeout(15000);
                sockets.add(socket);
                try { workers.execute(() -> handle(socket)); }
                catch (RejectedExecutionException busy) { sockets.remove(socket); socket.close(); }
            } catch (IOException error) { if (!closed) setState("failed", "http_socket_failed"); }
        }
    }

    private void handle(Socket socket) {
        boolean ownsUpload = false;
        File partial = new File(directory, "upload.part");
        try (Socket connection = socket) {
            InputStream input = connection.getInputStream();
            ByteArrayOutputStream header = new ByteArrayOutputStream();
            int terminator = 0;
            while (terminator != 0x0d0a0d0a && header.size() < 16384) {
                int value = input.read(); if (value < 0) return;
                header.write(value); terminator = (terminator << 8) | value;
            }
            if (terminator != 0x0d0a0d0a) { reply(connection, 431, "headers_too_large"); return; }
            String[] lines = new String(header.toByteArray(), StandardCharsets.US_ASCII).split("\r\n");
            String[] request = lines[0].split(" ");
            if (request.length != 3 || !request[2].equals("HTTP/1.1")) { reply(connection, 400, "invalid_request"); return; }
            Map<String,String> headers = new HashMap<>();
            for (int i=1; i<lines.length; i++) {
                int colon = lines[i].indexOf(':');
                if (colon < 1) { reply(connection, 400, "invalid_header"); return; }
                String key = lines[i].substring(0,colon).toLowerCase(Locale.ROOT);
                if (headers.put(key,lines[i].substring(colon+1).trim()) != null) {
                    reply(connection, 400, "duplicate_header"); return;
                }
            }
            byte[] supplied = headers.getOrDefault("authorization", "").getBytes(StandardCharsets.UTF_8);
            if (!MessageDigest.isEqual(supplied, ("Bearer " + token).getBytes(StandardCharsets.UTF_8))) {
                reply(connection, 401, "unauthorized"); return;
            }
            if (headers.containsKey("transfer-encoding")) { reply(connection, 400, "content_length_required"); return; }
            if (request[0].equals("GET") && request[1].equals("/debug/apk/status")) {
                reply(connection, 200, new JSONObject(status())); return;
            }
            if (request[0].equals("POST") && request[1].equals("/debug/apk/install")) {
                if (!Arrays.asList("uploaded", "settings_required").contains(stateName())) {
                    reply(connection, 409, "no_pending_apk"); return;
                }
                reply(connection, 202, "install_requested"); requestInstall(); return;
            }
            if (request[0].equals("DELETE") && request[1].equals("/debug/apk")) {
                if (uploading.get() || installing.get()) { reply(connection, 409, "install_busy"); return; }
                apk.delete(); setState("idle", ""); reply(connection, 200, "canceled"); return;
            }
            if (!request[0].equals("POST") || !request[1].equals("/debug/apk")) { reply(connection, 404, "not_found"); return; }
            long length;
            try { length = Long.parseLong(headers.getOrDefault("content-length", "-1")); }
            catch (NumberFormatException error) { reply(connection, 400, "invalid_length"); return; }
            if (length <= 0 || length > MAX_BYTES) { reply(connection, 413, "apk_size_limit"); return; }
            String sha = headers.getOrDefault("x-apk-sha256", "");
            if (!sha.matches("[0-9a-f]{64}")) { reply(connection, 400, "sha256_required"); return; }
            if (!uploading.compareAndSet(false, true)) { reply(connection, 409, "upload_busy"); return; }
            ownsUpload = true;
            if (Arrays.asList("preparing_install", "awaiting_confirmation", "installing", "settings_required").contains(stateName())) {
                reply(connection, 409, "install_busy"); return;
            }
            setState("receiving", "");
            apk.delete();
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[65536];
            long remaining = length;
            try (FileOutputStream output = new FileOutputStream(partial)) {
                while (remaining > 0) {
                    int count = input.read(buffer, 0, (int)Math.min(buffer.length, remaining));
                    if (count < 0) throw new EOFException();
                    output.write(buffer, 0, count); digest.update(buffer, 0, count); remaining -= count;
                }
                output.getFD().sync();
            }
            StringBuilder actual = new StringBuilder();
            for (byte value : digest.digest()) actual.append(String.format(Locale.ROOT,"%02x",value & 255));
            if (!actual.toString().equals(sha)) { setState("failed", "sha256_mismatch"); reply(connection, 422, "sha256_mismatch"); return; }
            String invalid = validate(partial);
            if (!invalid.isEmpty()) { setState("failed", invalid); reply(connection, 422, invalid); return; }
            if (!partial.renameTo(apk)) throw new IOException();
            synchronized(this) { state.put("sha256",sha); state.put("bytes",length); }
            setState("uploaded", "");
            reply(connection, 202, "uploaded");
            requestInstall();
        } catch (Exception error) {
            if (ownsUpload) setState("failed", "upload_interrupted");
        } finally {
            if (ownsUpload) { partial.delete(); uploading.set(false); }
            sockets.remove(socket);
        }
    }

    @SuppressWarnings("deprecation")
    private String validate(File candidate) throws Exception {
        PackageManager manager = activity.getPackageManager();
        PackageInfo incoming = manager.getPackageArchiveInfo(candidate.getAbsolutePath(), PackageManager.GET_SIGNATURES);
        if (incoming == null || incoming.applicationInfo == null) return "invalid_apk";
        if (!activity.getPackageName().equals(incoming.packageName)) return "package_mismatch";
        PackageInfo current = manager.getPackageInfo(activity.getPackageName(), PackageManager.GET_SIGNATURES);
        Set<Signature> trusted = new HashSet<>(Arrays.asList(current.signatures));
        if (incoming.signatures == null || !trusted.equals(new HashSet<>(Arrays.asList(incoming.signatures)))) return "signature_mismatch";
        if ((incoming.applicationInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0) return "debug_apk_required";
        long next = Build.VERSION.SDK_INT >= 28 ? incoming.getLongVersionCode() : incoming.versionCode;
        long previous = Build.VERSION.SDK_INT >= 28 ? current.getLongVersionCode() : current.versionCode;
        if (next < previous) return "version_downgrade";
        synchronized(this) {
            state.put("version_code",next); state.put("version_name",incoming.versionName);
            state.put("previous_update_time",current.lastUpdateTime);
        }
        return "";
    }

    private void requestInstall() {
        activity.runOnUiThread(() -> {
            if (closed || !apk.isFile() || installing.get()
                || !Arrays.asList("uploaded", "settings_required").contains(stateName())) return;
            if (Build.VERSION.SDK_INT >= 26 && !activity.getPackageManager().canRequestPackageInstalls()) {
                boolean opening = !stateName().equals("settings_required");
                setState("settings_required", "allow_unknown_app_source");
                if (opening) try {
                    activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:"+activity.getPackageName())));
                } catch (Exception error) { setState("failed", "installer_settings_unavailable"); }
                return;
            }
            if (!installing.compareAndSet(false, true)) return;
            setState("preparing_install", "");
            String action = activity.getPackageName()+".DEBUG_APK_RESULT";
            if (receiver == null) {
                receiver = new BroadcastReceiver() {
                    public void onReceive(Context context, Intent intent) {
                        int code = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
                        if (code == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                            Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                            if (confirm == null) { setState("failed", "missing_install_confirmation"); installing.set(false); return; }
                            setState("awaiting_confirmation", "");
                            try { activity.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); }
                            catch (Exception error) { setState("failed", "installer_unavailable"); installing.set(false); }
                        } else {
                            synchronized(ApkUpdateServer.this) {
                                try { state.put("installer_message",intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)); }
                                catch(Exception ignored) {}
                            }
                            setState(code == PackageInstaller.STATUS_SUCCESS ? "installed" : "failed",
                                code == PackageInstaller.STATUS_SUCCESS ? "" : "installer_status_"+code);
                            installing.set(false);
                            apk.delete();
                        }
                    }
                };
                if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, new IntentFilter(action), Context.RECEIVER_NOT_EXPORTED);
                else activity.registerReceiver(receiver, new IntentFilter(action));
            }
            new Thread(() -> {
                PackageInstaller installer = activity.getPackageManager().getPackageInstaller();
                int id = -1;
                try {
                    PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
                    params.setAppPackageName(activity.getPackageName()); params.setSize(apk.length());
                    if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED);
                    id = installer.createSession(params);
                    try (PackageInstaller.Session session = installer.openSession(id)) {
                        try (InputStream input = new FileInputStream(apk);
                             OutputStream output = session.openWrite("base.apk",0,apk.length())) {
                            byte[] bytes = new byte[65536]; int count;
                            while ((count=input.read(bytes)) != -1) output.write(bytes,0,count);
                            session.fsync(output);
                        }
                        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
                        if (Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE;
                        Intent callback = new Intent(action).setPackage(activity.getPackageName());
                        PendingIntent pending = PendingIntent.getBroadcast(activity,id,callback,flags);
                        synchronized(this) { state.put("session_id",id); }
                        setState("installing", "");
                        session.commit(pending.getIntentSender());
                    }
                } catch (Exception error) {
                    if (id >= 0) try { installer.abandonSession(id); } catch(Exception ignored) {}
                    setState("failed", "install_request_failed"); installing.set(false);
                }
            }, "NovaParty APK installer").start();
        });
    }

    // Called by the Debug service after returning from Android's source-permission settings.
    public void poll() {
        if (stateName().equals("settings_required") && Build.VERSION.SDK_INT >= 26
            && activity.getPackageManager().canRequestPackageInstalls()) requestInstall();
    }
    private synchronized String stateName() { return state.optString("state","idle"); }
    public synchronized String status() {
        try { JSONObject value = new JSONObject(state.toString()); value.put("state",stateName()); value.put("max_bytes",MAX_BYTES); return value.toString(); }
        catch (Exception ignored) { return "{}"; }
    }
    private synchronized void setState(String name, String error) {
        try {
            state.put("state",name); state.put("error",error); state.put("updated_at",System.currentTimeMillis());
            File temp = new File(directory,"status.part");
            try (FileOutputStream out = new FileOutputStream(temp)) { out.write(state.toString().getBytes(StandardCharsets.UTF_8)); out.getFD().sync(); }
            temp.renameTo(record);
        } catch (Exception ignored) {}
    }
    private void reply(Socket socket, int code, String message) throws Exception {
        reply(socket, code, new JSONObject().put("status",message));
    }
    private void reply(Socket socket, int code, JSONObject value) throws Exception {
        byte[] body = value.toString().getBytes(StandardCharsets.UTF_8);
        OutputStream out = socket.getOutputStream();
        out.write(("HTTP/1.1 "+code+" Response\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+body.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
        out.write(body); out.flush();
    }
    public void close() {
        closed = true;
        try { if(server != null) server.close(); } catch(IOException ignored) {}
        synchronized(sockets) { for(Socket socket:sockets) try { socket.close(); } catch(IOException ignored) {} }
        workers.shutdownNow();
        if(receiver != null) try { activity.unregisterReceiver(receiver); } catch(Exception ignored) {}
    }
}
