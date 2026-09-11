package com.lineagrafica.finanzas;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

public class MainActivity extends Activity {
    private static final String SUPABASE_URL = "https://chfrcfaldbdhmtgtoxcm.supabase.co";
    private static final String SUPABASE_PUBLISHABLE_KEY = "sb_publishable_1OVPFyUhEuvFsLu-n4c_kA_h8xZfJhM";
    private static final String APP_ORIGIN = "https://app.lineagrafica.local/";
    private static final int BUNDLED_FRONTEND_VERSION = 1;
    private static final String PREFS = "ota_frontend";
    private static final String PREF_VERSION = "version_code";
    private static final String PREF_SHA = "sha256";
    private static final String OTA_FILE = "frontend_ota.html";

    private WebView webView;
    private NativeRelease pendingNativeRelease;
    private boolean nativeUpdateCheckStarted = false;
    private boolean nativeDownloadInProgress = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        webView = new WebView(this);
        webView.setBackgroundColor(Color.rgb(7, 11, 20));
        setContentView(webView);
        configureWebView();

        new Thread(() -> {
            String html = prepareBestFrontend();
            runOnUiThread(() -> {
                if (!isFinishing() && webView != null) {
                    webView.loadDataWithBaseURL(APP_ORIGIN, html, "text/html", "UTF-8", null);
                    checkNativeUpdateAsync();
                }
            });
        }, "frontend-ota").start();
    }

    private void configureWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient());
    }

    private String prepareBestFrontend() {
        String bundled = readAsset("index.html");
        String cached = readValidCachedFrontend();
        int cachedVersion = getSharedPreferences(PREFS, MODE_PRIVATE).getInt(PREF_VERSION, BUNDLED_FRONTEND_VERSION);
        String current = cached != null && cachedVersion >= BUNDLED_FRONTEND_VERSION ? cached : bundled;
        int currentVersion = cached != null ? cachedVersion : BUNDLED_FRONTEND_VERSION;

        try {
            Release latest = fetchLatestRelease();
            if (latest != null && latest.versionCode > currentVersion && verifySha256(latest.html, latest.sha256)) {
                saveCachedFrontend(latest);
                current = latest.html;
            }
        } catch (Exception ignored) {
            // Sin Internet o Supabase temporalmente no disponible: usar última versión válida.
        }
        return injectDefaultSupabaseConfig(current);
    }

    private String injectDefaultSupabaseConfig(String html) {
        String script = "<script>(function(){try{if(!localStorage.getItem('finance_supabase_cfg_v1')){"
                + "localStorage.setItem('finance_supabase_cfg_v1',JSON.stringify({url:'"
                + SUPABASE_URL + "',key:'" + SUPABASE_PUBLISHABLE_KEY
                + "'}));}}catch(e){}})();</script>";
        int headEnd = html.indexOf("</head>");
        if (headEnd >= 0) return html.substring(0, headEnd) + script + html.substring(headEnd);
        return script + html;
    }

    private Release fetchLatestRelease() throws Exception {
        String endpoint = SUPABASE_URL
                + "/rest/v1/app_releases"
                + "?select=version_code,version,html,sha256"
                + "&is_active=eq.true&order=version_code.desc&limit=1";

        HttpURLConnection connection = openSupabaseGet(endpoint);
        String body;
        try (InputStream input = connection.getInputStream()) {
            body = readStream(input);
        } finally {
            connection.disconnect();
        }

        JSONArray rows = new JSONArray(body);
        if (rows.length() == 0) return null;
        JSONObject row = rows.getJSONObject(0);
        return new Release(
                row.getInt("version_code"),
                row.optString("version", ""),
                row.getString("html"),
                row.getString("sha256").toLowerCase(Locale.ROOT)
        );
    }

    private void checkNativeUpdateAsync() {
        if (nativeUpdateCheckStarted) return;
        nativeUpdateCheckStarted = true;
        new Thread(() -> {
            try {
                NativeRelease latest = fetchLatestNativeRelease();
                if (latest != null && latest.versionCode > getInstalledVersionCode()) {
                    runOnUiThread(() -> showNativeUpdateDialog(latest));
                }
            } catch (Exception ignored) {
                // La app sigue funcionando aunque el servidor de actualizaciones no esté disponible.
            }
        }, "native-update-check").start();
    }

    private NativeRelease fetchLatestNativeRelease() throws Exception {
        String endpoint = SUPABASE_URL
                + "/rest/v1/android_releases"
                + "?select=version_code,version,apk_url,sha256,notes,mandatory"
                + "&is_active=eq.true&order=version_code.desc&limit=1";

        HttpURLConnection connection = openSupabaseGet(endpoint);
        String body;
        try (InputStream input = connection.getInputStream()) {
            body = readStream(input);
        } finally {
            connection.disconnect();
        }

        JSONArray rows = new JSONArray(body);
        if (rows.length() == 0) return null;
        JSONObject row = rows.getJSONObject(0);
        return new NativeRelease(
                row.getInt("version_code"),
                row.optString("version", ""),
                row.getString("apk_url"),
                row.getString("sha256").toLowerCase(Locale.ROOT),
                row.optString("notes", ""),
                row.optBoolean("mandatory", false)
        );
    }

    private HttpURLConnection openSupabaseGet(String endpoint) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(endpoint).openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(3000);
        connection.setReadTimeout(5000);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("apikey", SUPABASE_PUBLISHABLE_KEY);
        connection.setRequestProperty("Cache-Control", "no-cache");
        int status = connection.getResponseCode();
        if (status < 200 || status >= 300) {
            connection.disconnect();
            throw new IllegalStateException("HTTP " + status);
        }
        return connection;
    }

    private long getInstalledVersionCode() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                return getPackageManager().getPackageInfo(getPackageName(), 0).getLongVersionCode();
            }
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionCode;
        } catch (Exception e) {
            return 0;
        }
    }

    private void showNativeUpdateDialog(NativeRelease release) {
        if (isFinishing()) return;
        StringBuilder message = new StringBuilder();
        message.append("Nueva versión: ").append(release.version);
        if (!release.notes.trim().isEmpty()) {
            message.append("\n\n").append(release.notes.trim());
        }
        message.append("\n\nLa APK se descargará y Android te pedirá confirmar la instalación.");

        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(release.mandatory ? "Actualización requerida" : "Actualización disponible")
                .setMessage(message.toString())
                .setPositiveButton("Actualizar", (dialog, which) -> startNativeUpdate(release));

        if (!release.mandatory) {
            builder.setNegativeButton("Más tarde", null);
        }

        AlertDialog dialog = builder.create();
        dialog.setCancelable(!release.mandatory);
        dialog.setCanceledOnTouchOutside(!release.mandatory);
        dialog.show();
    }

    private void startNativeUpdate(NativeRelease release) {
        if (nativeDownloadInProgress) return;
        if (release.apkUrl == null || !release.apkUrl.toLowerCase(Locale.ROOT).startsWith("https://")) {
            Toast.makeText(this, "URL de actualización no válida", Toast.LENGTH_LONG).show();
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !getPackageManager().canRequestPackageInstalls()) {
            pendingNativeRelease = release;
            Intent settingsIntent = new Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getPackageName())
            );
            startActivity(settingsIntent);
            Toast.makeText(this, "Permite instalar actualizaciones de E-conomic y vuelve a la app.", Toast.LENGTH_LONG).show();
            return;
        }

        pendingNativeRelease = null;
        downloadNativeApk(release);
    }

    private void downloadNativeApk(NativeRelease release) {
        nativeDownloadInProgress = true;
        try {
            DownloadManager manager = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
            Uri uri = Uri.parse(release.apkUrl);
            DownloadManager.Request request = new DownloadManager.Request(uri)
                    .setTitle("E-conomic " + release.version)
                    .setDescription("Descargando actualización…")
                    .setMimeType("application/vnd.android.package-archive")
                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    .setAllowedOverMetered(true)
                    .setAllowedOverRoaming(false)
                    .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS,
                            "E-conomic-" + release.versionCode + ".apk");

            long downloadId = manager.enqueue(request);
            Toast.makeText(this, "Descargando actualización…", Toast.LENGTH_SHORT).show();
            new Thread(() -> monitorDownload(manager, downloadId, release), "apk-download").start();
        } catch (Exception e) {
            nativeDownloadInProgress = false;
            Toast.makeText(this, "No se pudo iniciar la descarga", Toast.LENGTH_LONG).show();
        }
    }

    private void monitorDownload(DownloadManager manager, long downloadId, NativeRelease release) {
        try {
            for (int i = 0; i < 600; i++) {
                DownloadManager.Query query = new DownloadManager.Query().setFilterById(downloadId);
                try (Cursor cursor = manager.query(query)) {
                    if (cursor != null && cursor.moveToFirst()) {
                        int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
                        if (status == DownloadManager.STATUS_SUCCESSFUL) {
                            Uri downloadedUri = manager.getUriForDownloadedFile(downloadId);
                            if (downloadedUri == null || !verifySha256(downloadedUri, release.sha256)) {
                                manager.remove(downloadId);
                                runOnUiThread(() -> {
                                    nativeDownloadInProgress = false;
                                    Toast.makeText(this, "La actualización no superó la verificación de seguridad", Toast.LENGTH_LONG).show();
                                });
                                return;
                            }
                            runOnUiThread(() -> {
                                nativeDownloadInProgress = false;
                                launchInstaller(downloadedUri);
                            });
                            return;
                        }
                        if (status == DownloadManager.STATUS_FAILED) {
                            runOnUiThread(() -> {
                                nativeDownloadInProgress = false;
                                Toast.makeText(this, "Falló la descarga de la actualización", Toast.LENGTH_LONG).show();
                            });
                            return;
                        }
                    }
                }
                Thread.sleep(1000);
            }
            runOnUiThread(() -> {
                nativeDownloadInProgress = false;
                Toast.makeText(this, "La descarga tardó demasiado. Inténtalo de nuevo.", Toast.LENGTH_LONG).show();
            });
        } catch (Exception e) {
            runOnUiThread(() -> {
                nativeDownloadInProgress = false;
                Toast.makeText(this, "No se pudo verificar la actualización", Toast.LENGTH_LONG).show();
            });
        }
    }

    private boolean verifySha256(Uri uri, String expected) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = getContentResolver().openInputStream(uri)) {
            if (input == null) return false;
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder hex = new StringBuilder();
        for (byte b : digest.digest()) hex.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        return hex.toString().equalsIgnoreCase(expected == null ? "" : expected.trim());
    }

    private void launchInstaller(Uri apkUri) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(apkUri, "application/vnd.android.package-archive");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } catch (Exception e) {
            Toast.makeText(this, "No se pudo abrir el instalador de Android", Toast.LENGTH_LONG).show();
        }
    }

    private String readValidCachedFrontend() {
        File file = new File(getFilesDir(), OTA_FILE);
        if (!file.isFile()) return null;
        try {
            String html = readFile(file);
            String expected = getSharedPreferences(PREFS, MODE_PRIVATE).getString(PREF_SHA, "");
            if (expected == null || expected.isEmpty() || !verifySha256(html, expected)) {
                file.delete();
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().remove(PREF_VERSION).remove(PREF_SHA).apply();
                return null;
            }
            return html;
        } catch (Exception e) {
            return null;
        }
    }

    private void saveCachedFrontend(Release release) throws Exception {
        File target = new File(getFilesDir(), OTA_FILE);
        File temp = new File(getFilesDir(), OTA_FILE + ".tmp");
        try (FileOutputStream output = new FileOutputStream(temp, false)) {
            output.write(release.html.getBytes(StandardCharsets.UTF_8));
            output.flush();
            output.getFD().sync();
        }
        if (target.exists() && !target.delete()) throw new IllegalStateException("No se pudo reemplazar OTA");
        if (!temp.renameTo(target)) throw new IllegalStateException("No se pudo activar OTA");
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putInt(PREF_VERSION, release.versionCode)
                .putString(PREF_SHA, release.sha256)
                .apply();
    }

    private boolean verifySha256(String text, String expected) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] hash = digest.digest(text.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex = new StringBuilder(hash.length * 2);
        for (byte b : hash) hex.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        return hex.toString().equalsIgnoreCase(expected == null ? "" : expected.trim());
    }

    private String readAsset(String name) {
        try (InputStream input = getAssets().open(name)) {
            return readStream(input);
        } catch (Exception e) {
            return "<!doctype html><html><body style='background:#070b14;color:white;font-family:sans-serif;padding:24px'>No se pudo cargar E-conomic. Vuelve a abrirla.</body></html>";
        }
    }

    private String readFile(File file) throws Exception {
        try (InputStream input = new FileInputStream(file)) {
            return readStream(input);
        }
    }

    private String readStream(InputStream input) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        return new String(output.toByteArray(), StandardCharsets.UTF_8);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (pendingNativeRelease != null
                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && getPackageManager().canRequestPackageInstalls()) {
            NativeRelease release = pendingNativeRelease;
            pendingNativeRelease = null;
            downloadNativeApk(release);
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    private static final class Release {
        final int versionCode;
        final String version;
        final String html;
        final String sha256;

        Release(int versionCode, String version, String html, String sha256) {
            this.versionCode = versionCode;
            this.version = version;
            this.html = html;
            this.sha256 = sha256;
        }
    }

    private static final class NativeRelease {
        final int versionCode;
        final String version;
        final String apkUrl;
        final String sha256;
        final String notes;
        final boolean mandatory;

        NativeRelease(int versionCode, String version, String apkUrl, String sha256, String notes, boolean mandatory) {
            this.versionCode = versionCode;
            this.version = version;
            this.apkUrl = apkUrl;
            this.sha256 = sha256;
            this.notes = notes;
            this.mandatory = mandatory;
        }
    }
}
