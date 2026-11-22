# Building the Android APK / App Bundle

Prerequisites: Flutter 3.24+ (`flutter doctor` all green for Android), Android SDK 34+, JDK 17.

```bash
cd app
python3 tool/setup_platforms.py           # first time only
cp env/dev.example.json env/prod.json     # production Supabase URL + anon key (+ FIREBASE_*)
flutter pub get
flutter analyze && flutter test
```

## Debug APK (for testing on a phone)

```bash
flutter build apk --debug --dart-define-from-file=env/prod.json
# → build/app/outputs/flutter-apk/app-debug.apk
```

## Release signing

```bash
keytool -genkey -v -keystore android/app/mauqa-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mauqa
```
Create `android/key.properties` (git-ignored):
```
storePassword=…
keyPassword=…
keyAlias=mauqa
storeFile=mauqa-release.jks
```
In `android/app/build.gradle` (or `build.gradle.kts`) load `key.properties` into a `signingConfigs.release` block and
set `buildTypes.release.signingConfig = signingConfigs.release` (standard Flutter instructions:
docs.flutter.dev/deployment/android#configure-signing-in-gradle).

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=env/prod.json   # smaller APKs per CPU
flutter build appbundle --release --dart-define-from-file=env/prod.json             # for Google Play
```

## Checklist before publishing
- `minSdkVersion` 21+ (firebase_messaging requirement) — the Flutter default satisfies this.
- Deep link `io.mauqa.app://login-callback` is in the manifest (added by `setup_platforms.py`) and in Supabase Auth redirect URLs.
- Android 13+: the app requests notification permission at sign-in when push is configured.
- Replace the launcher icon (`flutter_launcher_icons` or Android Studio Image Asset).
- Play Console → Data safety: declare email/phone, profile data, documents (user-provided, encrypted in transit, deletable).
