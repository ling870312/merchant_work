#!/usr/bin/env python3
"""把 uni-app 原生插件注册进 iOS 宿主 Info.plist 的 dcloud_uniplugins。

DCloud iOS 运行时通过 Info.plist 里的 dcloud_uniplugins 数组把
JS 端 `uni.requireNativePlugin(name)` 映射到原生 ObjC 类。
只把源码编进二进制、只写 PandoraApi.bundle/feature.plist 都是不够的：
Info.plist 缺 dcloud_uniplugins 时 requireNativePlugin 会返回 null，
前端诊断即为 "plugin object: unresolved; methods: none"，也就是
"当前 iOS 宿主未集成监控播放原生插件"。

格式参考 DCloud 官方文档：
https://nativesupport.dcloud.net.cn/NativePlugin/offline_package/ios

用法:
    python3 inject-ios-uniplugins.py <Info.plist> <manifest.json> \
        [--plugin-id DoorMaster-Monitor-Player]

只注入 --plugin-id 指定的插件（可重复），其余现有 dcloud_uniplugins
条目保持不变。这样 CI 里暂时禁用的插件不会被错误注册。
"""
import argparse
import json
import plistlib
import sys
from pathlib import Path


def load_manifest_plugins(manifest_path: Path):
    """返回 manifest 中 app-plus.nativePlugins 或 plus.nativePlugins 的 iOS 配置。"""
    with open(manifest_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    app_plus = data.get('app-plus') or {}
    plus = data.get('plus') or {}
    return (app_plus.get('nativePlugins') or plus.get('nativePlugins') or {})


def normalize_plugin_entry(plugin, fallback_name):
    return {
        'type': str(plugin.get('type') or 'module'),
        'name': str(plugin.get('name') or fallback_name),
        'class': str(plugin.get('class') or ''),
    }


def build_dcloud_entry(plugin_id, config):
    ios = (config or {}).get('ios') or {}
    hooks_class = str(ios.get('hooksClass') or '')
    raw_plugins = ios.get('plugins') or []

    entries = []
    for raw in raw_plugins:
        entry = normalize_plugin_entry(raw, plugin_id)
        if entry['class']:
            entries.append(entry)
    if not entries:
        raise ValueError(f'{plugin_id} 的 ios.plugins 为空或缺少 class')

    return {
        'hooksClass': hooks_class,
        'plugins': entries,
    }


def existing_entry_has_any(existing, names):
    if not isinstance(existing, dict):
        return False
    raw_plugins = existing.get('plugins') or []
    if not isinstance(raw_plugins, list):
        return False
    existing_names = {
        str(item.get('name') or '')
        for item in raw_plugins
        if isinstance(item, dict)
    }
    return bool(existing_names & set(names))


def main():
    parser = argparse.ArgumentParser(description='Inject dcloud_uniplugins into iOS Info.plist')
    parser.add_argument('plist', help='Info.plist 路径')
    parser.add_argument('manifest', help='uni-app 项目 manifest.json 路径')
    parser.add_argument('--plugin-id', action='append', default=[], help='只注入指定插件，可重复')
    args = parser.parse_args()

    plist_path = Path(args.plist)
    manifest_path = Path(args.manifest)
    if not plist_path.is_file():
        print(f'::error::Info.plist 不存在: {plist_path}', file=sys.stderr)
        sys.exit(1)
    if not manifest_path.is_file():
        print(f'::error::manifest.json 不存在: {manifest_path}', file=sys.stderr)
        sys.exit(1)

    try:
        native_plugins = load_manifest_plugins(manifest_path)
    except Exception as exc:
        print(f'::error::manifest.json 解析失败: {exc}', file=sys.stderr)
        sys.exit(1)

    if not isinstance(native_plugins, dict) or not native_plugins:
        print('::error::manifest 中未声明 nativePlugins', file=sys.stderr)
        sys.exit(1)

    selected_ids = args.plugin_id or list(native_plugins.keys())

    try:
        with open(plist_path, 'rb') as f:
            info = plistlib.load(f)
    except Exception as exc:
        print(f'::error::Info.plist 解析失败: {exc}', file=sys.stderr)
        sys.exit(1)

    if not isinstance(info, dict):
        print(f'::error::Info.plist 顶层不是 dict: {type(info).__name__}', file=sys.stderr)
        sys.exit(1)

    existing = info.get('dcloud_uniplugins')
    if existing is None:
        existing = []
    if not isinstance(existing, list):
        print(f'::error::dcloud_uniplugins 已是 {type(existing).__name__}，期望 array', file=sys.stderr)
        sys.exit(1)

    target_names = set()
    new_entries = []
    for plugin_id in selected_ids:
        config = native_plugins.get(plugin_id)
        if not isinstance(config, dict):
            print(f'::warning::manifest 未找到插件 {plugin_id}，跳过', file=sys.stderr)
            continue
        try:
            entry = build_dcloud_entry(plugin_id, config)
        except ValueError as exc:
            print(f'::error::{exc}', file=sys.stderr)
            sys.exit(1)
        for item in entry['plugins']:
            target_names.add(item['name'])
        new_entries.append(entry)

    if not new_entries:
        print('::error::没有可注入的插件条目', file=sys.stderr)
        sys.exit(1)

    kept_entries = [
        item for item in existing
        if not existing_entry_has_any(item, target_names)
    ]
    info['dcloud_uniplugins'] = kept_entries + new_entries

    with open(plist_path, 'wb') as f:
        plistlib.dump(info, f)

    print(f'dcloud_uniplugins 注入 {len(new_entries)} 个插件包（target names: {sorted(target_names)}）')
    for entry in info['dcloud_uniplugins']:
        print(f'  hooksClass={entry.get("hooksClass")!r} plugins={entry.get("plugins")}')


if __name__ == '__main__':
    main()
