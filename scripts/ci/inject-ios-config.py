#!/usr/bin/env python3
"""统一修改 iOS 工程 Info.plist，替代 macOS 专有的 PlistBuddy。

在 Linux (ubuntu runner) 上执行，把所有 Info.plist 修改一次性完成：
- dcloud_appkey（SDK 运行时校验）
- CFBundleName / CFBundleDisplayName（应用名）
- CFBundleIdentifier（包名）
- CFBundleIconName
- CFBundleShortVersionString / CFBundleVersion（版本号）
- 清理重复/损坏的隐私键并重写

用法: python3 inject-ios-config.py <Info.plist 路径> \
        --appkey <key> --display-name <name> --bundle-id <id> \
        --version-name <ver> --version-code <code>
"""
import plistlib
import re
import sys
import argparse


def main():
    parser = argparse.ArgumentParser(description='Inject iOS config into Info.plist')
    parser.add_argument('plist', help='Path to Info.plist')
    parser.add_argument('--appkey', required=True, help='DCloud appkey')
    parser.add_argument('--display-name', required=True, help='CFBundleDisplayName')
    parser.add_argument('--bundle-id', required=True, help='CFBundleIdentifier')
    parser.add_argument('--version-name', required=True, help='CFBundleShortVersionString')
    parser.add_argument('--version-code', required=True, help='CFBundleVersion')
    args = parser.parse_args()

    with open(args.plist, 'rb') as f:
        pl = plistlib.load(f)

    # 1. DCloud appkey
    pl['dcloud_appkey'] = args.appkey
    print(f'dcloud_appkey={args.appkey}')

    # 2. 应用名
    pl['CFBundleDisplayName'] = args.display_name
    pl['CFBundleName'] = 'Merchant'
    print(f'CFBundleDisplayName={args.display_name}')
    print('CFBundleName=Merchant')

    # 3. Bundle Identifier
    pl['CFBundleIdentifier'] = args.bundle_id
    print(f'CFBundleIdentifier={args.bundle_id}')

    # 4. App Icon
    pl['CFBundleIconName'] = 'AppIcon'
    print('CFBundleIconName=AppIcon')

    # 5. 版本号
    pl['CFBundleShortVersionString'] = args.version_name
    pl['CFBundleVersion'] = args.version_code
    print(f'CFBundleShortVersionString={args.version_name}')
    print(f'CFBundleVersion={args.version_code}')

    # 6. 清理重复/损坏的隐私键并重写
    removed = []
    for k in list(pl.keys()):
        if re.match(r'^NS.*(UsageDescription|WhenInUse|Always|Tracking)', k) or ' - ' in k:
            del pl[k]
            removed.append(k)
    if removed:
        print(f'已删除隐私键: {removed}')

    pl['NSCameraUsageDescription'] = '用于扫描商品条码、识别商品'
    pl['NSMicrophoneUsageDescription'] = '用于门店远程对讲语音通话'
    pl['NSPhotoLibraryUsageDescription'] = '用于上传商品图片、门店资料图片'
    pl['NSBluetoothAlwaysUsageDescription'] = '用于连接门店蓝牙设备（打印机、门禁控制器等）'
    pl['NSLocationWhenInUseUsageDescription'] = '用于获取门店位置、展示周边服务'
    print('隐私用途说明已清理并重写')

    with open(args.plist, 'wb') as f:
        plistlib.dump(pl, f)
    print('✅ Info.plist 配置全部完成')


if __name__ == '__main__':
    main()
