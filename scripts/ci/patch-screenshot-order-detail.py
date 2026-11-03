#!/usr/bin/env python3
"""仅用于模拟器截图构建：让订单卡片点击后进入订单详情页。

原因：当前 App 的 OrderCard 只提供“退款/回放”按钮，卡片本身没有详情跳转，
无法从销售列表点击进入详情。该修改只作用于 ios-simulator-test 克隆出的源码，
真机/IPA 构建不受影响。
"""
import pathlib
import sys

FUNC = '''

function openOrderDetail() {
  const o = props.order
  const query = [
    `salesOrderId=${o.salesOrderId || o.id}`,
    `orderId=${o.id}`,
    `paymentOrderId=${encodeURIComponent(o.paymentOrderId || '')}`,
    `storeId=${o.storeId || 0}`,
    `ordersn=${encodeURIComponent(o.orderNo || '')}`,
  ].join('&')
  uni.navigateTo({ url: `/packages/trade/order-detail/index?${query}` })
}
'''


def main():
    repo = pathlib.Path(sys.argv[1])
    target = repo / 'src/packages/trade/components/OrderCard.vue'
    text = target.read_text(encoding='utf-8')

    if '@tap="openOrderDetail"' in text:
        print('OrderCard 已包含详情跳转，跳过')
        return

    if '<view class="order-card">' not in text:
        raise SystemExit('未找到 OrderCard 根节点，源码结构可能已变化')

    text = text.replace('<view class="order-card">',
                        '<view class="order-card" @tap="openOrderDetail">', 1)

    index = text.rfind('</script>')
    if index < 0:
        raise SystemExit('OrderCard 未找到 </script>')
    text = text[:index] + FUNC + text[index:]
    target.write_text(text, encoding='utf-8')
    print('已为截图构建添加订单卡片 -> 订单详情跳转')


if __name__ == '__main__':
    main()
