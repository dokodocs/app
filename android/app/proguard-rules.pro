# R8/ProGuard keep rules for the release build.
#
# Some transitive dependencies reference optional networking/crypto classes
# (Huawei HMS, Cronet/Chromium, Conscrypt) that aren't on the classpath and
# aren't used by DokoDocs. R8 treats these missing references as errors in
# full mode; silence them so shrinking can complete. These are warnings
# about code paths the app never executes.
-dontwarn org.chromium.net.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn com.huawei.**

# Flutter deferred components / Play Core (referenced by the engine but the
# app doesn't use dynamic feature delivery).
-dontwarn com.google.android.play.core.**

# Keep annotations used for reflection by some plugins.
-keepattributes *Annotation*
