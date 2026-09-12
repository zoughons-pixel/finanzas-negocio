package com.lineagrafica.finanzas;

import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

/** E-conomic v1.4: exportación nativa y segura de reportes PDF/Excel. */
public class MainActivityV14 extends MainActivityV13 {
    private static final int MAX_REPORT_BASE64_CHARS = 30 * 1024 * 1024;
    private static final String PDF_MIME = "application/pdf";
    private static final String XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WebView webView = findWebView();
        if (webView != null) {
            webView.addJavascriptInterface(new ReportBridge(), "EconNative");
        }
    }

    private final class ReportBridge {
        @JavascriptInterface
        public void saveReport(String fileName, String mimeType, String base64Data) {
            new Thread(() -> saveReportInternal(fileName, mimeType, base64Data), "report-export").start();
        }
    }

    private void saveReportInternal(String fileName, String mimeType, String base64Data) {
        if (!PDF_MIME.equals(mimeType) && !XLSX_MIME.equals(mimeType)) {
            showToast("Formato de reporte no permitido");
            return;
        }
        if (base64Data == null || base64Data.isEmpty() || base64Data.length() > MAX_REPORT_BASE64_CHARS) {
            showToast("El reporte es demasiado grande o está vacío");
            return;
        }

        try {
            byte[] bytes = Base64.decode(base64Data, Base64.DEFAULT);
            String safeName = sanitizeFileName(fileName, mimeType);
            Uri uri;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.Downloads.DISPLAY_NAME, safeName);
                values.put(MediaStore.Downloads.MIME_TYPE, mimeType);
                values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/E-conomic");
                values.put(MediaStore.Downloads.IS_PENDING, 1);

                uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (uri == null) throw new IllegalStateException("No se pudo crear el archivo");
                try (OutputStream output = getContentResolver().openOutputStream(uri)) {
                    if (output == null) throw new IllegalStateException("No se pudo abrir el archivo");
                    output.write(bytes);
                    output.flush();
                } catch (Exception e) {
                    getContentResolver().delete(uri, null, null);
                    throw e;
                }
                values.clear();
                values.put(MediaStore.Downloads.IS_PENDING, 0);
                getContentResolver().update(uri, values, null, null);
            } else {
                File base = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS);
                if (base == null) base = getFilesDir();
                File dir = new File(base, "Reports");
                if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("No se pudo crear la carpeta");
                File file = uniqueFile(dir, safeName);
                try (FileOutputStream output = new FileOutputStream(file)) {
                    output.write(bytes);
                    output.flush();
                    output.getFD().sync();
                }
                uri = FileProvider.getUriForFile(this, getPackageName() + ".fileprovider", file);
            }

            Uri finalUri = uri;
            runOnUiThread(() -> {
                Toast.makeText(this, "Reporte guardado en E-conomic", Toast.LENGTH_SHORT).show();
                openOrShareReport(finalUri, mimeType, safeName);
            });
        } catch (Exception e) {
            showToast("No se pudo guardar el reporte");
        }
    }

    private String sanitizeFileName(String name, String mimeType) {
        String safe = name == null ? "Reporte" : name.trim();
        safe = safe.replaceAll("[^A-Za-z0-9._ -]", "_");
        if (safe.isEmpty()) safe = "Reporte";
        String ext = PDF_MIME.equals(mimeType) ? ".pdf" : ".xlsx";
        if (!safe.toLowerCase().endsWith(ext)) safe += ext;
        return safe;
    }

    private File uniqueFile(File dir, String name) {
        File candidate = new File(dir, name);
        if (!candidate.exists()) return candidate;
        int dot = name.lastIndexOf('.');
        String stem = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int i = 2; i < 1000; i++) {
            candidate = new File(dir, stem + " (" + i + ")" + ext);
            if (!candidate.exists()) return candidate;
        }
        return new File(dir, stem + "-" + System.currentTimeMillis() + ext);
    }

    private void openOrShareReport(Uri uri, String mimeType, String fileName) {
        try {
            Intent view = new Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, mimeType)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(view);
        } catch (Exception ignored) {
            try {
                Intent share = new Intent(Intent.ACTION_SEND)
                        .setType(mimeType)
                        .putExtra(Intent.EXTRA_STREAM, uri)
                        .putExtra(Intent.EXTRA_SUBJECT, fileName)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                startActivity(Intent.createChooser(share, "Compartir reporte"));
            } catch (Exception e) {
                Toast.makeText(this, "Reporte guardado. No hay una app para abrirlo.", Toast.LENGTH_LONG).show();
            }
        }
    }

    private void showToast(String message) {
        runOnUiThread(() -> Toast.makeText(this, message, Toast.LENGTH_LONG).show());
    }

    private WebView findWebView() {
        View content = findViewById(android.R.id.content);
        if (!(content instanceof ViewGroup)) return null;
        return findWebView((ViewGroup) content);
    }

    private WebView findWebView(ViewGroup group) {
        for (int i = 0; i < group.getChildCount(); i++) {
            View child = group.getChildAt(i);
            if (child instanceof WebView) return (WebView) child;
            if (child instanceof ViewGroup) {
                WebView nested = findWebView((ViewGroup) child);
                if (nested != null) return nested;
            }
        }
        return null;
    }
}
