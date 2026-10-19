#!/usr/bin/env python3
"""Reject a wrong app or an IPA built without the image-capable iOS SDK."""
import json
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    mains = [name for name in archive.namelist()
             if name.startswith('Payload/') and name.count('/') == 2
             and name.endswith('.app/Info.plist')]
    if len(mains) != 1:
        raise SystemExit('Expected one main app in the IPA')
    info = plistlib.loads(archive.read(mains[0]))
    if info.get('CFBundleIdentifier') != 'com.D3GG62L9X8.LoopFollow':
        raise SystemExit('Unexpected LoopFollow bundle identity')
    if not info.get('DTSDKName', '').startswith('iphoneos27.'):
        raise SystemExit('IPA was not built with the iOS 27 SDK')
    if int(info.get('CFBundleVersion', '0')) < 24:
        raise SystemExit('Build number predates the native scanner')
    result = {key: info.get(key) for key in (
        'CFBundleIdentifier', 'CFBundleShortVersionString',
        'CFBundleVersion', 'DTSDKName', 'DTXcodeBuild')}
with open('native-plate-ipa-verification.json', 'w') as output:
    json.dump(result, output, indent=2)
print(json.dumps(result))
