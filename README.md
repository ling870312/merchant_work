# merchant_work — 商家 APP iOS 打包 CI 工程仓（公开）

本仓为 **公开 CI-only 工程仓**，仅包含 GitHub Actions 工作流编排与 CI 辅助脚本，不含项目源码与任何明文敏感值：

- APP 源码与渠道身份（appid / bundleId / appkey 等）位于**私有源码仓**；
- iOS SDK、MobileVLCKit 与预集成工程（含渠道身份）位于**私有资产仓**，绝不发布到本仓；
- 签名证书、描述文件、Team ID、App Store Connect Key、源码仓部署私钥等全部经 **GitHub Secrets** 注入，按渠道独立命名（`<凭据名>_<渠道大写>`）；
- 本仓公开以使用免费的 macOS runner；敏感资产仅按需拉取至 runner，不落地本仓存储。

## 工作流

| 工作流 | Runner | 说明 |
|---|---|---|
| `prepare-ios-project.yml` | macos-14 | 从私有资产仓取 SDK / 插件 → 集成生成预集成工程 → 回传私有资产仓 |
| `build-ios.yml` | ubuntu + macos-15 | 构建源码 / 注入工程 → Xcode 签名导出 IPA → 可选上传 App Store Connect |
| `diagnose-asc.yml` | macos-15 | 查询 App Store Connect 构建处理状态 |

## 目录

```
.github/workflows/   三个工作流
scripts/ci/          CI 辅助脚本（渠道配置读取 / 配置注入 / 插件集成 / ASC 诊断）
```

## 快速开始

1. 按 [SECRETS.md](./SECRETS.md) 配置 Secrets；
2. （SDK / 原生插件变更时）触发 `Prepare iOS Pre-integrated Project`，刷新预集成工程；
3. 触发 `Build iOS IPA`（选择渠道 / 版本 / 构建号），产物经 App Store Connect（TestFlight）分发；
4. （可选）触发 `Diagnose ASC Build Status` 查看构建处理状态。

## 安全约束

- 本仓**严禁**出现任何明文密钥、证书、私钥、appkey、真实渠道名 / 包名及私有仓地址；
- 各渠道的签名 / ASC / appkey 凭据相互独立，禁止混用；
- SDK、预集成工程等资产只存于私有资产仓，禁止上传本仓；`ASSET_PAT` 仅授权该私有资产仓。
