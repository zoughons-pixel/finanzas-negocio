package com.lineagrafica.finanzas;

import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.graphics.Color;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;

/** Device gate, independent of JavaScript/session/network. Never stores biometric data. */
public class MainActivityV21 extends MainActivityV16 {
    private static final String PREFS = "economic_device_security";
    private static final int AUTH = BiometricManager.Authenticators.BIOMETRIC_WEAK
            | BiometricManager.Authenticators.DEVICE_CREDENTIAL;
    private WebView content;
    private LinearLayout shield;
    private TextView message;
    private BiometricPrompt prompt;
    private boolean locked, authenticating;
    private Boolean requestedSetting;

    private boolean enabled() { return getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("enabled", false); }

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        content = locate((ViewGroup) findViewById(android.R.id.content));
        shield = new LinearLayout(this);
        shield.setOrientation(LinearLayout.VERTICAL);
        shield.setGravity(android.view.Gravity.CENTER);
        shield.setPadding(48, 48, 48, 48);
        shield.setBackgroundColor(Color.rgb(11,16,32));
        message = new TextView(this);
        message.setTextColor(Color.WHITE);
        message.setTextSize(20);
        message.setText("E-conomic está bloqueado");
        shield.addView(message);
        Button retry = new Button(this);
        retry.setText("Desbloquear");
        retry.setOnClickListener(v -> authenticate(null));
        shield.addView(retry);
        addContentView(shield, new FrameLayout.LayoutParams(-1,-1));
        prompt = new BiometricPrompt(this, ContextCompat.getMainExecutor(this), new BiometricPrompt.AuthenticationCallback() {
            @Override public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
                authenticating = false;
                if (requestedSetting != null) getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean("enabled", requestedSetting).commit();
                requestedSetting = null; locked = false; reveal();
                if (content != null) content.evaluateJavascript("window.dispatchEvent(new Event('economic-security-change'))", null);
            }
            @Override public void onAuthenticationError(int code, CharSequence error) {
                authenticating = false; requestedSetting = null;
                locked = enabled();
                message.setText("E-conomic está bloqueado\n" + error);
                if (!locked) reveal();
            }
        });
        if (content != null) content.addJavascriptInterface(new SecurityBridge(), "EconSecurity");
        locked = enabled();
        if (locked) cover(); else reveal();
    }

    private void cover() { if (shield != null) shield.setVisibility(View.VISIBLE); if (content != null) content.setVisibility(View.INVISIBLE); }
    private void reveal() { if (shield != null) shield.setVisibility(View.GONE); if (content != null) content.setVisibility(View.VISIBLE); }
    private void authenticate(Boolean setting) {
        if (authenticating || isFinishing()) return;
        if (BiometricManager.from(this).canAuthenticate(AUTH) != BiometricManager.BIOMETRIC_SUCCESS) {
            new android.app.AlertDialog.Builder(this).setTitle("Protección del dispositivo")
                .setMessage("Configura una huella, rostro o PIN de pantalla en los ajustes de Android y vuelve a intentarlo.")
                .setPositiveButton("Entendido", null).show();
            return;
        }
        requestedSetting = setting; authenticating = true; cover();
        prompt.authenticate(new BiometricPrompt.PromptInfo.Builder()
            .setTitle("Desbloquear E-conomic")
            .setSubtitle("Usa tu biometría o el PIN de este dispositivo")
            .setAllowedAuthenticators(AUTH).build());
    }

    @Override protected void onResume() {
        super.onResume();
        if (shield == null || authenticating) return;
        if (enabled() && locked) { cover(); authenticate(null); } else reveal();
    }
    @Override protected void onPause() { if (enabled() || authenticating) cover(); super.onPause(); }
    @Override protected void onStop() { if (enabled() && !authenticating) locked = true; super.onStop(); }
    @Override public void onBackPressed() { if (locked || authenticating) moveTaskToBack(true); else super.onBackPressed(); }

    public final class SecurityBridge {
        @JavascriptInterface public boolean isEnabled() { return enabled(); }
        @JavascriptInterface public boolean isAvailable() { return BiometricManager.from(MainActivityV21.this).canAuthenticate(AUTH) == BiometricManager.BIOMETRIC_SUCCESS; }
        @JavascriptInterface public void setEnabled(boolean value) { runOnUiThread(() -> authenticate(value)); }
        @JavascriptInterface public void lock() { runOnUiThread(() -> { if (enabled()) { locked=true; cover(); authenticate(null); } }); }
    }
    private WebView locate(ViewGroup parent) {
        for (int i=0; i<parent.getChildCount(); i++) {
            View child=parent.getChildAt(i);
            if (child instanceof WebView) return (WebView)child;
            if (child instanceof ViewGroup) { WebView found=locate((ViewGroup)child); if(found!=null) return found; }
        }
        return null;
    }
}
