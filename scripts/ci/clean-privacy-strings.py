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
        'NSPhotoLibraryUsageDescription': '用于上传商品图片、门店资料图片',
        'NSBluetoothAlwaysUsageDescription': '用于连接门店蓝牙设备（打印机、门禁控制器等）',
        'NSLocationWhenInUseUsageDescription': '用于获取门店位置、展示周边服务',
    }
    for key, value in required_privacy.items():
        pl[key] = value
    print('隐私用途说明已补齐:', ','.join(required_privacy))

    # 麦克风：当前 iOS 版本未启用远程对讲（TRTC 未集成、intercomRuntime 关闭），
    # 不申请麦克风权限。SDK 模板自带的该键一并移除，避免"声明却从不使用"被审核问询。
    if pl.pop('NSMicrophoneUsageDescription', None) is not None:
        print('已移除 NSMicrophoneUsageDescription（当前版本不使用麦克风）')

    # ATT：App 不做跨 App 追踪，不能保留该键，否则 App Store Connect 要求
    # 声明「数据用于追踪」而无法提交审核。SDK 启动发出的跟踪授权请求
    # 由编译进 App 的 ATTGuard.m 直接返回「拒绝」，不会弹窗也不会崩溃。
    if pl.pop('NSUserTrackingUsageDescription', None) is not None:
        print('已移除 NSUserTrackingUsageDescription（不做追踪，避免提交审核被拦）')

    with open(p, 'wb') as f:
        plistlib.dump(pl, f)


if __name__ == '__main__':
    main()
