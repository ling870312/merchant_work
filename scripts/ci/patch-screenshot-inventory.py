#!/usr/bin/env python3
"""仅用于模拟器截图构建：把商品管理页“盘点”入口改为直接进入盘点页。

原因：App 端的 goInventory 会先调用 uni.scanCode 拉起原生扫码（需要摄像头），
GitHub 模拟器没有摄像头，流程会卡在扫码页，无法截到盘点页面。
该修改只作用于 ios-simulator-test 工作流克隆出的源码，真机/IPA 构建不受影响。
"""
import pathlib
import sys


def main():
    repo = pathlib.Path(sys.argv[1])
    target = repo / 'src/packages/goods/goods/index.vue'
    text = target.read_text(encoding='utf-8')

    start = text.find('function goInventory() {')
    if start < 0:
        raise SystemExit('未找到 goInventory()，源码结构可能已变化')

    brace = text.find('{', start)
    depth = 0
    end = -1
    for i in range(brace, len(text)):
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end < 0:
        raise SystemExit('goInventory() 花括号不匹配')

    replacement = (
        'function goInventory() {\n'
        '  // CI 截图构建：模拟器无摄像头，直接进入盘点页（不影响真机/IPA）\n'
        '  openInventoryPage()\n'
        '}'
    )
    text = text[:start] + replacement + text[end:]
    target.write_text(text, encoding='utf-8')
    print('已修改模拟器截图构建的 goInventory：直接进入盘点页')


if __name__ == '__main__':
    main()
