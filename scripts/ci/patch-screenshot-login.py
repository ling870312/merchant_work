#!/usr/bin/env python3
"""仅用于模拟器截图构建：默认勾选登录协议。

原因：Maestro 点击“我已阅读并同意”文字时可能误触旁边的《用户协议》链接，
打开 App 内浏览器导致后续登录步骤全部作用在协议页上。
截图构建中直接默认勾选协议（界面仍显示已勾选），真机/IPA 构建不受影响。
"""
import pathlib
import sys


def main():
    repo = pathlib.Path(sys.argv[1])
    target = repo / 'src/pages/login/index.vue'
    text = target.read_text(encoding='utf-8')

    changed = False

    old_init = 'const agreeProtocols = ref(false)'
    if old_init in text:
        text = text.replace(old_init, 'const agreeProtocols = ref(true)', 1)
        changed = True

    # 截图时点击“登 录”可能因页面回弹偏移而误触协议开关，
    # 这里把切换逻辑改成始终勾选，避免登录按钮被禁用。
    old_toggle = 'agreeProtocols.value = !agreeProtocols.value'
    if old_toggle in text:
        text = text.replace(old_toggle, 'agreeProtocols.value = true', 1)
        changed = True

    if not changed:
        print('登录协议已默认勾选且不可取消，跳过')
        return

    if 'const agreeProtocols = ref(true)' not in text:
        raise SystemExit('未找到 agreeProtocols 初始化，源码结构可能已变化')

    target.write_text(text, encoding='utf-8')
    print('已为截图构建设置登录协议默认勾选且不可取消')


if __name__ == '__main__':
    main()
