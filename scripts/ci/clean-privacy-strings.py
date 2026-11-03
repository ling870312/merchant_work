#!/usr/bin/env python3
"""清理 Info.plist 中损坏的隐私用途说明键并补齐必需用途说明。

HBuilder SDK 模板的 Info.plist 自带一批损坏的隐私键（如
"NSLocationWhenInUseUsageDescription - 2" 带 - 2 后缀、空值的
"NSLocationWhenInUseDescription"），PlistBuddy 增量 Delete 只能删第一个
同名键，残留损坏键导致 Apple 后台校验（ITMS-90683）解析失败、判二进制无效。

本脚本只删除损坏键（" - 2" 后缀 / 空值），保留 SDK 自带的其它隐私键，再覆盖写入
必需的用途说明。禁止"先删光再补写固定几个"：一旦删掉 App/SDK 实际调用的
UsageDescription，调用对应 API 时会被 TCC 以隐私违规直接终止（SIGABRT）。

用法: python3 clean-privacy-strings.py <Info.plist 路径>
"""
import plistlib
import re
import sys


def main():
    p = sys.argv[1]
    with open(p, 'rb') as f:
        pl = plistlib.load(f)

    # 只删除损坏键（" - 2" 后缀、空值），保留 SDK 自带的其它隐私键
    privacy_pattern = re.compile(r'^NS.*(UsageDescription|WhenInUse|Always|Tracking)')
    removed = []
    for k in list(pl.keys()):
        if ' - ' in k:
            del pl[k]
            removed.append(k)
            continue
        if privacy_pattern.match(k):
            value = pl.get(k)
            if not isinstance(value, str) or not value.strip():
                del pl[k]
                removed.append(k)
    print('已删除损坏隐私键:', removed)

    # 覆盖写入必需、合规的用途说明
    required_privacy = {
        'NSCameraUsageDescription': '用于扫描商品条码、识别商品',
        'NSMicrophoneUsageDescription': '用于门店远程对讲语音通话',
        'NSPhotoLibraryUsageDescription': '用于上传商品图片、门店资料图片',
        'NSBluetoothAlwaysUsageDescription': '用于连接门店蓝牙设备（打印机、门禁控制器等）',
        'NSLocationWhenInUseUsageDescription': '用于获取门店位置、展示周边服务',
        # ATT 请求必须配套该键，否则 iOS 会以 TCC 隐私违规直接终止 App
        # （HBuilder/广告 SDK 启动时会调用 ATTrackingManager，缺失即崩溃）
        'NSUserTrackingUsageDescription': '用于向您提供更相关的服务与内容，并改进产品体验',
    }
    for key, value in required_privacy.items():
        pl[key] = value

    with open(p, 'wb') as f:
        plistlib.dump(pl, f)
    print('隐私用途说明已补齐:', ','.join(required_privacy))


if __name__ == '__main__':
    main()
