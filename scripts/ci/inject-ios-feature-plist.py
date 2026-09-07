#!/usr/bin/env python3
"""注入 DCloud iOS 离线工程的 feature.plist 兼容注册条目。

注意：uni-app 原生插件（JS 端 uni.requireNativePlugin）在 iOS 上的实际
注册表是 Info.plist 的 dcloud_uniplugins，由 inject-ios-uniplugins.py 维护；
feature.plist 主要用于 5+/HTML5+ 内置模块映射。这里继续写一份是为了兼容
不同 SDK 版本/文档要求，并保留 SDK 自带的其他条目不动。

用法: python3 inject-ios-feature-plist.py <sdk-root 或工程根目录>

在多个候选位置查找 feature.plist 并注入 DoorMaster-Monitor-Player 的
module / component 注册条目，保留 SDK 自带的其他条目不动。
（TRTC 当前在 CI 中禁用，不注入其条目。）
"""
import plistlib
import sys
from pathlib import Path

# 要注册的原生插件映射（JS 模块名 -> 原生类）。
# 字段格式遵循 docs/ios-preintegrated-project-setup.md 步骤 4 的标准：
#   class: [类名]（数组），type: module | component
PLUGINS = {
    'DoorMaster-Monitor-Player': {
        'class': ['DMMonitorPlayerModule'],
        'type': 'module',
    },
    'doorMasterMonitorPlayerView': {
        'class': ['DMMonitorPlayerView'],
        'type': 'component',
    },
}

# feature.plist 在不同 SDK 版本/解压层级下的候选相对路径。
# SDK 4.x 工程实际 Copy Bundle Resources 的是 SDK/Bundles/PandoraApi.bundle，
# 因此把它放在最前面，避免改到工程目录下未参与打包的同名副本。
CANDIDATE_REL = [
    'SDK/Bundles/PandoraApi.bundle/feature.plist',
    'HBuilder-Hello/HBuilder-Hello/PandoraApi.bundle/feature.plist',
    'HBuilder-Hello/PandoraApi.bundle/feature.plist',
    'PandoraApi.bundle/feature.plist',
    'HBuilder-Hello/HBuilder-Hello/feature.plist',
    'HBuilder-Hello/feature.plist',
    'feature.plist',
]


def find_feature_plist(root: Path):
    """在 root 下查找 feature.plist，优先 PandoraApi.bundle 内的，
    排除 SDK 自带示例目录，避免改错文件。"""
    for rel in CANDIDATE_REL:
        p = root / rel
        if p.is_file():
            return p

    # 兜底递归搜索，排除示例/SDK 文档目录里的同名文件
    for p in root.rglob('feature.plist'):
        sp = str(p)
        if '/Examples/' in sp or '/Samples/' in sp or '/Doc/' in sp:
            continue
        # 优先返回 PandoraApi.bundle 内的
        if 'PandoraApi' in sp:
            return p

    # 最后兜底：任何 feature.plist（排除示例）
    for p in root.rglob('feature.plist'):
        sp = str(p)
        if '/Examples/' in sp or '/Samples/' in sp or '/Doc/' in sp:
            continue
        return p

    return None


def _as_array(value):
    """把 class 字段规范化为数组形式以便比较。"""
    if isinstance(value, list):
        return value
    if value is None:
        return []
    return [value]


def main():
    if len(sys.argv) < 2:
        print('用法: inject-ios-feature-plist.py <sdk-root 或工程根目录>', file=sys.stderr)
        sys.exit(2)

    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f'::error::根目录不存在: {root}', file=sys.stderr)
        sys.exit(1)

    plist_path = find_feature_plist(root)
    if plist_path is None:
        print(f'::error::未找到 feature.plist（搜索根: {root}）', file=sys.stderr)
        print('::error::DCloud iOS SDK 的 PandoraApi.bundle/feature.plist 是原生插件注册表，', file=sys.stderr)
        print('::error::缺它 requireNativePlugin 返回 null，插件方法无法被 JS 调用', file=sys.stderr)
        sys.exit(1)

    print(f'feature.plist: {plist_path}')

    with open(plist_path, 'rb') as f:
        pl = plistlib.load(f)

    if not isinstance(pl, dict):
        print(f'::error::feature.plist 顶层不是 dict: {type(pl).__name__}', file=sys.stderr)
        sys.exit(1)

    changed = []
    for name, spec in PLUGINS.items():
        existing = pl.get(name)
        # 比较时把 class 规范为数组，容忍 SDK 旧版用 string 而非 array
        same = (
            existing is not None
            and isinstance(existing, dict)
            and _as_array(existing.get('class')) == spec['class']
            and existing.get('type') == spec['type']
        )
        if same:
            print(f'  {name}: 已存在且匹配，跳过')
            continue
        # 统一写为标准格式（class 为数组、type 为字符串）
        pl[name] = dict(spec)
        changed.append(name)

    if changed:
        with open(plist_path, 'wb') as f:
            plistlib.dump(pl, f)
        print(f'✅ 已注入插件映射: {", ".join(changed)}')
    else:
        print('✅ 所有插件映射已存在且匹配，无需修改')

    print('--- feature.plist 最终注册条目 ---')
    for name in PLUGINS:
        entry = pl.get(name)
        print(f'  {name} -> {entry}')

    # 列出注册表中的全部条目数，便于确认未误删 SDK 自带条目
    print(f'feature.plist 顶层 key 数: {len(pl)}')


if __name__ == '__main__':
    main()
