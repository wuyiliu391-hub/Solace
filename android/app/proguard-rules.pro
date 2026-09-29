-keep class io.flutter.** { *; }
-keep class com.baseflow.geolocator.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn io.flutter.**
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

-keep class com.solace.solace.** { *; }

-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.lyokone.location.** { *; }

-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.PluginRegistry$PluginRegistrantCallback { *; }
-keep class * extends io.flutter.app.FlutterPluginRegistry { *; }

-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.filepicker.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.bumptech.glide.** { *; }

-keep class * implements io.flutter.plugin.common.MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.EventChannel$StreamHandler { *; }

-keepclassmembers class * {
    *** registerWith(io.flutter.plugin.common.PluginRegistry);
}

-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

-keep class com.openfile.** { *; }
-dontwarn com.openfile.**

-keep class io.flutter.plugins.webviewflutter.** { *; }
