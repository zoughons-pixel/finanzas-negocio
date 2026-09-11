package com.lineagrafica.finanzas;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

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
        return current;
    }

    private Release fetchLatestRelease() throws Exception {
        String endpoint = SUPABASE_URL
                + "/rest/v1/app_releases"
                + "?select=version_code,version,html,sha256"
                + "&is_active=eq.true&order=version_code.desc&limit=1";

        HttpURLConnection connection = (HttpURLConnection) new URL(endpoint).openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(2500);
        connection.setReadTimeout(3500);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("apikey", SUPABASE_PUBLISHABLE_KEY);
        connection.setRequestProperty("Cache-Control", "no-cache");

        int status = connection.getResponseCode();
        if (status < 200 || status >= 300) {
            connection.disconnect();
            throw new IllegalStateException("OTA HTTP " + status);
        }

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
            return "<!doctype html><html><body style='background:#070b14;color:white;font-family:sans-serif;padding:24px'>No se pudo cargar la aplicación. Vuelve a abrirla.</body></html>";
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
}
