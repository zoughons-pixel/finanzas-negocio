package com.lineagrafica.finanzas;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;

/** E-conomic v1.6: puente nativo para alertas financieras locales. */
public class MainActivityV16 extends MainActivityV14 {
    private static final int NOTIFICATION_PERMISSION_REQUEST = 1601;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        FinanceAlertReceiver.ensureChannel(this);
        WebView webView = findWebView();
        if (webView != null) {
            webView.addJavascriptInterface(new NotificationBridge(), "EconNotify");
        }
    }

    private final class NotificationBridge {
        @JavascriptInterface
        public boolean hasPermission() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                    && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
            return androidx.core.app.NotificationManagerCompat.from(MainActivityV16.this).areNotificationsEnabled();
        }

        @JavascriptInterface
        public void requestPermission() {
            runOnUiThread(() -> {
                FinanceAlertReceiver.ensureChannel(MainActivityV16.this);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                        && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, NOTIFICATION_PERMISSION_REQUEST);
                } else {
                    Toast.makeText(MainActivityV16.this, "Notificaciones activadas", Toast.LENGTH_SHORT).show();
                }
            });
        }

        @JavascriptInterface
        public void schedule(String key, long triggerAtMillis, String title, String body) {
            FinanceAlertReceiver.schedule(MainActivityV16.this, key, triggerAtMillis, title, body);
        }

        @JavascriptInterface
        public void cancel(String key) {
            FinanceAlertReceiver.cancel(MainActivityV16.this, key);
        }

        @JavascriptInterface
        public void showNow(String key, String title, String body) {
            FinanceAlertReceiver.show(MainActivityV16.this, key, title, body);
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
}
