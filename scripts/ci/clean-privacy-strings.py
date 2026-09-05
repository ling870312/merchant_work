#!/usr/bin/env python3
"""清理 Info.plist 中的隐私用途说明键并统一重写。

HBuilder SDK 模板的 Info.plist 自带一批重复/损坏的隐私键（如
"NSLocationWhenInUseUsageDescription - 2" 带 - 2 后缀、空值的
"NSLocationWhenInUseDescription"），PlistBuddy 增量 Delete 只能删第一个
同名键，残留损坏键导致 Apple 后台校验（ITMS-90683）解析失败、判二进制无效。

本脚本用正则彻底删除所有隐私描述键（含重复/损坏），再统一写入干净的用途说明。

用法: python3 clean-privacy-strings.py <Info.plist 路径>
"""
import plistlib
import re
import sys


def main():
    p = sys.argv[1]
    with open(p, 'rb') as f:
        pl = plistlib.load(f)

    # 删除所有隐私描述键（含重复/损坏键，如 " - 2" 后缀）
    removed = []
    for k in list(pl.keys()):
        if re.match(r'^NS.*(UsageDescription|WhenInUse|Always|Tracking)', k) or ' - ' in k:
            del pl[k]
            removed.append(k)
    print('已删除隐私键:', removed)

    # 重新写入干净、合规的用途说明
    pl['NSCameraUsageDescription'] = '用于扫描商品条码、识别商品'
    pl['NSMicrophoneUsageDescription'] = '用于门店远程对讲语音通话'
    pl['NSPhotoLibraryUsageDescription'] = '用于上传商品图片、门店资料图片'
    pl['NSBluetoothAlwaysUsageDescription'] = '用于连接门店蓝牙设备（打印机、门禁控制器等）'
    pl['NSLocationWhenInUseUsageDescription'] = '用于获取门店位置、展示周边服务'

    with open(p, 'wb') as f:
        plistlib.dump(pl, f)
    print('隐私用途说明已清理并重写')


if __name__ == '__main__':
    main()
