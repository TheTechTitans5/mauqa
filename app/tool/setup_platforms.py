"""
Generates the Android/iOS platform folders with `flutter create` (keeping lib/ and test/ untouched) and patches:
  * AndroidManifest.xml: INTERNET + POST_NOTIFICATIONS permissions, deep link for auth callbacks,
    <queries> for url_launcher (https, mailto), app label.
  * iOS Info.plist: URL scheme for auth callbacks.
Usage (from app/):  python3 tool/setup_platforms.py
"""
import os
import re
import shutil
import subprocess
import sys

SCHEME = 'io.mauqa.app'
HOST = 'login-callback'

def run(cmd):
    print('$', ' '.join(cmd))
    # On Windows, flutter is flutter.bat; shutil.which finds it (subprocess alone does not).
    exe = shutil.which(cmd[0]) or cmd[0]
    subprocess.check_call([exe] + cmd[1:])
    
def patch_android():
    path = 'android/app/src/main/AndroidManifest.xml'
    s = open(path, encoding='utf-8').read()
    perms = ['android.permission.INTERNET', 'android.permission.POST_NOTIFICATIONS']
    for p in perms:
        if p not in s:
            s = s.replace('<application', f'<uses-permission android:name="{p}"/>\n    <application', 1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="Mauqa"', s, count=1)
    if HOST not in s:
        deep_link = f'''
            <intent-filter android:autoVerify="false">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="{SCHEME}" android:host="{HOST}"/>
            </intent-filter>'''
        s = s.replace('</activity>', deep_link + '\n        </activity>', 1)
    if '<queries>' not in s:
        queries = '''
    <queries>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>
        <intent><action android:name="android.intent.action.PROCESS_TEXT"/><data android:mimeType="text/plain"/></intent>
    </queries>'''
        s = s.replace('</manifest>', queries + '\n</manifest>', 1)
    open(path, 'w', encoding='utf-8').write(s)
    print('patched', path)

def patch_ios():
    path = 'ios/Runner/Info.plist'
    if not os.path.exists(path):
        return
    s = open(path, encoding='utf-8').read()
    if SCHEME not in s:
        block = f'''	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLSchemes</key>
			<array><string>{SCHEME}</string></array>
		</dict>
	</array>
'''
        s = s.replace('</dict>\n</plist>', block + '</dict>\n</plist>', 1)
        open(path, 'w', encoding='utf-8').write(s)
        print('patched', path)

if __name__ == '__main__':
    if not os.path.exists('pubspec.yaml'):
        sys.exit('Run from the app/ directory')
    if not os.path.exists('android'):
        run(['flutter', 'create', '--org', 'io.mauqa', '--project-name', 'mauqa', '--platforms=android,ios', '.'])
    patch_android()
    patch_ios()
    print('Done. Next: flutter pub get && flutter run --dart-define-from-file=env/dev.json')
