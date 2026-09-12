package com.lineagrafica.finanzas;

import android.Manifest;
import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONObject;

import java.util.Map;

/** Alarmas locales para vencimientos, presupuestos y metas de E-conomic. */
public class FinanceAlertReceiver extends BroadcastReceiver {
    private static final String CHANNEL_ID = "economic_finance_alerts";
    private static final String CHANNEL_NAME = "Alertas financieras";
    private static final String PREFS = "economic_notification_schedules";
    private static final String ACTION_ALERT = "com.lineagrafica.finanzas.FINANCE_ALERT";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            ensureChannel(context);
            rescheduleAll(context);
            return;
        }

        String key = intent == null ? "alert" : intent.getStringExtra("key");
        String title = intent == null ? "E-conomic" : intent.getStringExtra("title");
        String body = intent == null ? "Tienes una alerta financiera." : intent.getStringExtra("body");
        if (key == null || key.trim().isEmpty()) key = "alert";
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply();
        show(context, key, title, body);
    }

    public static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager == null) return;
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_DEFAULT
            );
            channel.setDescription("Vencimientos, presupuestos y metas de E-conomic");
            manager.createNotificationChannel(channel);
        }
    }

    public static void schedule(Context context, String key, long triggerAtMillis, String title, String body) {
        key = safeKey(key);
        title = safeText(title, 120, "E-conomic");
        body = safeText(body, 500, "Tienes una alerta financiera.");
        if (triggerAtMillis <= System.currentTimeMillis() + 5000L) {
            show(context, key, title, body);
            return;
        }
        try {
            JSONObject data = new JSONObject();
            data.put("when", triggerAtMillis);
            data.put("title", title);
            data.put("body", body);
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit().putString(key, data.toString()).apply();
            scheduleAlarm(context, key, triggerAtMillis, title, body);
        } catch (Exception ignored) {
        }
    }

    private static void scheduleAlarm(Context context, String key, long when, String title, String body) {
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarms == null) return;
        PendingIntent pending = alertPendingIntent(context, key, title, body, PendingIntent.FLAG_UPDATE_CURRENT);
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, when, pending);
    }

    public static void cancel(Context context, String key) {
        key = safeKey(key);
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pending = alertPendingIntent(context, key, "", "", PendingIntent.FLAG_NO_CREATE);
        if (alarms != null && pending != null) alarms.cancel(pending);
        if (pending != null) pending.cancel();
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply();
    }

    public static void show(Context context, String key, String title, String body) {
        ensureChannel(context);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return;
        }
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return;

        key = safeKey(key);
        title = safeText(title, 120, "E-conomic");
        body = safeText(body, 500, "Tienes una alerta financiera.");
        Intent launch = new Intent(context, MainActivityV16.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(
                context,
                requestCode("open:" + key),
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.app_icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setContentIntent(content);
        try {
            NotificationManagerCompat.from(context).notify(requestCode(key), builder.build());
        } catch (SecurityException ignored) {
        }
    }

    private static PendingIntent alertPendingIntent(Context context, String key, String title, String body, int modeFlag) {
        Intent intent = new Intent(context, FinanceAlertReceiver.class)
                .setAction(ACTION_ALERT + "." + key)
                .putExtra("key", key)
                .putExtra("title", title)
                .putExtra("body", body);
        int flags = modeFlag | PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getBroadcast(context, requestCode(key), intent, flags);
    }

    private static void rescheduleAll(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        Map<String, ?> all = prefs.getAll();
        long now = System.currentTimeMillis();
        for (Map.Entry<String, ?> entry : all.entrySet()) {
            try {
                JSONObject data = new JSONObject(String.valueOf(entry.getValue()));
                long when = data.optLong("when", 0L);
                String title = data.optString("title", "E-conomic");
                String body = data.optString("body", "Tienes una alerta financiera.");
                if (when > now + 5000L) {
                    scheduleAlarm(context, safeKey(entry.getKey()), when, title, body);
                } else {
                    prefs.edit().remove(entry.getKey()).apply();
                }
            } catch (Exception e) {
                prefs.edit().remove(entry.getKey()).apply();
            }
        }
    }

    private static String safeKey(String key) {
        String value = key == null ? "alert" : key.trim();
        if (value.isEmpty()) value = "alert";
        value = value.replaceAll("[^A-Za-z0-9:_-]", "_");
        return value.length() > 120 ? value.substring(0, 120) : value;
    }

    private static String safeText(String text, int max, String fallback) {
        String value = text == null ? "" : text.trim();
        if (value.isEmpty()) value = fallback;
        return value.length() > max ? value.substring(0, max) : value;
    }

    private static int requestCode(String key) {
        return (key == null ? 0 : key.hashCode()) & 0x7fffffff;
    }
}
