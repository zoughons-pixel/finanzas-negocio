package com.lineagrafica.finanzas;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.widget.Toast;

/**
 * E-conomic v1.3: habilita el selector nativo de fotos/archivos para los
 * comprobantes cargados desde el frontend WebView.
 */
public class MainActivityV13 extends MainActivity {
    private static final int FILE_CHOOSER_REQUEST = 1301;

    private ValueCallback<android.net.Uri[]> filePathCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        WebView webView = findWebView();
        if (webView == null) return;

        webView.getSettings().setAllowContentAccess(true);
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(
                    WebView webView,
                    ValueCallback<android.net.Uri[]> callback,
                    FileChooserParams fileChooserParams
            ) {
                if (filePathCallback != null) {
                    filePathCallback.onReceiveValue(null);
                }
                filePathCallback = callback;

                try {
                    Intent intent = fileChooserParams.createIntent();
                    startActivityForResult(intent, FILE_CHOOSER_REQUEST);
                    return true;
                } catch (Exception e) {
                    filePathCallback = null;
                    Toast.makeText(MainActivityV13.this,
                            "No se pudo abrir el selector de comprobantes",
                            Toast.LENGTH_LONG).show();
                    return false;
                }
            }
        });
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
            ValueCallback<android.net.Uri[]> callback = filePathCallback;
            filePathCallback = null;
            if (callback != null) {
                android.net.Uri[] results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
                callback.onReceiveValue(results);
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onDestroy() {
        if (filePathCallback != null) {
            filePathCallback.onReceiveValue(null);
            filePathCallback = null;
        }
        super.onDestroy();
    }
}
