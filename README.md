# merchant_work — 商家 APP iOS 打包工程仓（公开 / CI-only）

本仓库为 **公开 CI 工程仓**，只存放 GitHub Actions 工作流编排与 CI 脚本，**不含任何项目源码与明文敏感信息**。
APP 源码主体托管在 Gitee 私有仓，CI 运行时用部署私钥浅克隆；所有敏感信息（Gitee 地址/分支/私钥、iOS 签名证书/描述文件/Team ID、DCloud appkey、App Store Connect API Key）全部通过 GitHub Secrets 注入。

## 为什么是公开仓

GitHub 对**公开仓库**的 runner（含 macOS）免费、不消耗私有仓库的付费配额。本仓设为 Public 以使用免费 macOS 额度，同时通过以下机制保证敏感信息不泄露：

- 工作流文件与 CI 脚本中**不出现任何明文敏感值**（Gitee 地址、appkey、bundleId、证书等均未硬编码）；
- 渠道身份（bundleId / appid / displayName / profileSpecifier）运行时从 Gitee 源码 `oem_config/<channel>/oem.json` 动态读取；
- DCloud appkey、iOS 签名凭据、ASC API Key 均按渠道从 Secret 间接引用（`<凭据名>_<渠道大写>`），适配各渠道分属不同公司/Apple 账号；
- **预集成 iOS 工程（含 SDK / MobileVLCKit / 插件 / 渠道 appid 与 appkey）托管在私有资产仓**，本仓 `Build iOS IPA` 仅用 `ASSET_PAT` 只读拉取，不持有、不生成这些资产；
- 运行时日志对 Secret 值自动掩码，并对渠道身份额外 `::add-mask::`；
- 仅 `workflow_dispatch`（手动触发，默认分支）可访问 Secret；fork 的 PR 默认无法读取 Secret。

## 工作流

| 工作流 | Runner | 用途 |
|---|---|---|
| `build-ios.yml` | ubuntu-latest + macos-15 | 双 Job 打包 IPA：ubuntu 构建源码/注入工程，macOS 做 Xcode 编译签名 + 上传 ASC |
| `diagnose-asc.yml` | macos-15 | 诊断 App Store Connect 构建处理状态，定位 Invalid Binary |

> 预集成 iOS 工程（`ios-project.zip`，tag `ios-project-v1`）由**私有资产仓**的 `Prepare iOS Pre-integrated Project` 工作流维护（瘦身 SDK 4.87 + DoorMaster-Monitor-Player + MobileVLCKit + 渠道身份），不在本仓。

## OEM 渠道

渠道清单与身份配置（bundleId / appid / displayName / profileSpecifier / appkey）统一维护在 Gitee 源码仓 `oem_config/<渠道>/oem.json`，**本仓不落任何真实渠道名与品牌名**。运行时通过 `workflow_dispatch` 的 `oem_channel` 输入（小写渠道码）选择渠道。

## 目录结构

```
.github/workflows/
  build-ios.yml              # 双 Job 打包 IPA
  diagnose-asc.yml           # ASC 诊断
scripts/ci/
  read-ios-channel.sh        # 从 oem.json 读渠道 iOS 身份
  inject-ios-config.py       # 注入 Info.plist（appkey/名称/包名/版本）
  sync-ios-appicons.sh        # 注入 App 图标
  diagnose-asc.rb            # 查询 ASC 构建状态
```

> 其余脚本（`apply-oem-config.ps1` / `sync-theme-assets.ps1` / `install-ios-signing.sh` / `integrate-plugins.rb` 等）位于 **Gitee 源码仓**或**私有资产仓**中，CI 运行时从 clone 的 `repo/` 中调用，不在本工程仓。

## 快速开始

1. **配置 Secrets**：见 [SECRETS.md](./SECRETS.md)，按清单逐个配置（含 `ASSET_PAT` 只读访问私有资产仓）。
2. **打包 IPA**：手动触发 `Build iOS IPA`，选择渠道/版本/Gitee 分支（留空则用默认 Secret）。预集成工程自动从私有资产仓拉取最新 `ios-project-v1`。
3. **（可选）诊断**：触发 `Diagnose ASC Build Status` 查看 ASC 处理状态。

## 安全约束

- 严禁在本仓提交任何明文密钥、证书、私钥、appkey、Gitee 地址等敏感值；
- 新增渠道时，需在 GitHub Secrets 增加该渠道全员配置：`DLOUD_APPKEY_<渠道大写>`、`IOS_P12_BASE64_<渠道大写>`、`IOS_P12_PASSWORD_<渠道大写>`、`IOS_MOBILEPROVISION_BASE64_<渠道大写>`、`IOS_TEAM_ID_<渠道大写>`；若该渠道需上传 ASC，再配 `ASC_API_KEY_ID_<渠道大写>` / `ASC_ISSUER_ID_<渠道大写>` / `ASC_API_KEY_P8_<渠道大写>`（诊断用另配 `IOS_BUNDLE_ID_<渠道大写>`）。各渠道可能属不同公司，签名与 ASC 凭据**按渠道独立**，不要混用；
- `ASSET_PAT` 只授权私有资产仓（Contents 只读即可）；**不要**把 SDK / 预集成工程等资产上传到本公开仓；
- 渠道身份改动走 Gitee 源码 `oem_config/<channel>/oem.json`，无需改本仓工作流。
