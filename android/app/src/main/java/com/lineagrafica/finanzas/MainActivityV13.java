package com.lineagrafica.finanzas;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.Parcelable;
import android.provider.MediaStore;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import java.io.File;

/**
 * E-conomic v1.3: selector nativo de comprobantes con galería, archivos y cámara.
 */
public class MainActivityV13 extends MainActivity {
    private static final int FILE_CHOOSER_REQUEST = 1301;
    private static final String CAMERA_PREFIX = "economic_receipt_";

    private ValueCallback<Uri[]> filePathCallback;
    private Uri pendingCameraUri;
    private File pendingCameraFile;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        cleanupOldCameraFiles();

        WebView webView = findWebView();
        if (webView == null) return;

        // Android entrega las selecciones del sistema como content:// URIs.
        webView.getSettings().setAllowContentAccess(true);
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(
                    WebView webView,
                    ValueCallback<Uri[]> callback,
                    FileChooserParams params
            ) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = callback;
                pendingCameraUri = null;
                pendingCameraFile = null;

                try {
                    Intent pickerIntent = params.createIntent();
                    Intent cameraIntent = acceptsImages(params) ? createCameraIntent() : null;
                    Intent launchIntent;

                    if (params.isCaptureEnabled() && cameraIntent != null) {
                        launchIntent = cameraIntent;
                    } else if (cameraIntent != null) {
                        Intent chooser = Intent.createChooser(pickerIntent, "Seleccionar comprobante");
                        chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, new Parcelable[]{cameraIntent});
                        launchIntent = chooser;
                    } else {
                        launchIntent = pickerIntent;
                    }

                    startActivityForResult(launchIntent, FILE_CHOOSER_REQUEST);
                    return true;
                } catch (Exception e) {
                    clearFileChooser(false);
                    Toast.makeText(MainActivityV13.this,
                            "No se pudo abrir la cámara o el selector de comprobantes",
                            Toast.LENGTH_LONG).show();
                    return false;
                }
            }
        });
    }

    private boolean acceptsImages(WebChromeClient.FileChooserParams params) {
        String[] types = params.getAcceptTypes();
        if (types == null || types.length == 0) return true;
        for (String type : types) {
            if (type == null || type.trim().isEmpty() || "*/*".equals(type) || type.startsWith("image/")) {
                return true;
            }
        }
        return false;
    }

    private Intent createCameraIntent() {
        try {
            Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            if (intent.resolveActivity(getPackageManager()) == null) return null;

            File dir = getExternalFilesDir(Environment.DIRECTORY_PICTURES);
            if (dir == null) dir = getCacheDir();
            if (!dir.exists() && !dir.mkdirs()) return null;

            pendingCameraFile = File.createTempFile(CAMERA_PREFIX, ".jpg", dir);
            pendingCameraUri = FileProvider.getUriForFile(
                    this,
                    getPackageName() + ".fileprovider",
                    pendingCameraFile
            );
            intent.putExtra(MediaStore.EXTRA_OUTPUT, pendingCameraUri);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            return intent;
        } catch (Exception e) {
            pendingCameraFile = null;
            pendingCameraUri = null;
            return null;
        }
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

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == FILE_CHOOSER_REQUEST) {
            ValueCallback<Uri[]> callback = filePathCallback;
            filePathCallback = null;
            if (callback != null) {
                Uri[] results = null;
                if (resultCode == RESULT_OK) {
                    boolean pickerReturnedData = data != null && (data.getData() != null || data.getClipData() != null);
                    if (!pickerReturnedData && pendingCameraUri != null && pendingCameraFile != null
                            && pendingCameraFile.isFile() && pendingCameraFile.length() > 0) {
                        results = new Uri[]{pendingCameraUri};
                    } else {
                        results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
                    }
                }
                callback.onReceiveValue(results);
            }
            if (resultCode != RESULT_OK && pendingCameraFile != null) {
                pendingCameraFile.delete();
            }
            pendingCameraUri = null;
            pendingCameraFile = null;
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private void clearFileChooser(boolean notify) {
        if (filePathCallback != null) {
            filePathCallback.onReceiveValue(null);
            filePathCallback = null;
        }
        if (pendingCameraFile != null) pendingCameraFile.delete();
        pendingCameraFile = null;
        pendingCameraUri = null;
        if (notify) {
            Toast.makeText(this, "Selección de comprobante cancelada", Toast.LENGTH_SHORT).show();
        }
    }

    private void cleanupOldCameraFiles() {
        long cutoff = System.currentTimeMillis() - 24L * 60L * 60L * 1000L;
        File[] dirs = new File[]{getExternalFilesDir(Environment.DIRECTORY_PICTURES), getCacheDir()};
        for (File dir : dirs) {
            if (dir == null || !dir.isDirectory()) continue;
            File[] files = dir.listFiles();
            if (files == null) continue;
            for (File file : files) {
                if (file.getName().startsWith(CAMERA_PREFIX) && file.lastModified() < cutoff) {
                    file.delete();
                }
            }
        }
    }

    @Override
    protected void onDestroy() {
        clearFileChooser(false);
        super.onDestroy();
    }
}
