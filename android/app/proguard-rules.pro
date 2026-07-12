# android/app/proguard-rules.pro
# Referenced by build.gradle's proguardFiles but was missing entirely, so the
# release build was minifying with zero custom keep rules — R8's default
# rules don't know about Firebase/Play Billing's reflection-based init, so
# this is a common source of release-only crashes (works in debug where
# minification is off, breaks on a real signed release build).

# ── Flutter ──────────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ── Firebase (Core / Messaging / Crashlytics) ───────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics needs line numbers and source file names preserved to
# symbolicate stack traces meaningfully.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── Google Play Billing (in_app_purchase / in_app_purchase_android) ────
-keep class com.android.billingclient.** { *; }
-keep class com.android.vending.billing.** { *; }
-dontwarn com.android.billingclient.**

# ── Kotlin metadata (reflection-based libraries rely on this) ──────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ── General Android component safety net ────────────────────────────────
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
