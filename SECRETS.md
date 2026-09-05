# GitHub Secrets 配置清单

本仓为公开工程仓，所有敏感信息通过 GitHub Secrets 注入。下表为完整清单，按需配置。
文档中不使用任何真实渠道名 / 品牌名 / 包名，一律以占位符表示：

- `<渠道>`：小写渠道码，如 `xxx`（须与 `workflow_dispatch` 的 `oem_channel` input 值一致）
- `<渠道大写>`：该渠道码的大写形式（GitHub Secret 名不区分大小写，统一按大写命名）
- `<组织>/<仓>`：Gitee 私有仓地址

## Secret 清单

### Gitee 源码访问（全局，不按渠道）

| Secret 名 | 用途 | 必需 | 取值示例 / 获取方式 |
|---|---|---|---|
| `GITEE_SSH_KEY` | Gitee 仓库部署私钥（只读，ed25519），CI 浅克隆源码 | ✅ 必须 | Gitee 仓库「部署公钥」对应的私钥全文（含 BEGIN/END 行） |
| `GITEE_REPO` | Gitee 仓库 SSH 地址 | ✅ 必须 | `git@gitee.com:<组织>/<仓>.git` |
| `GITEE_BRANCH` | Gitee 要克隆的分支 | ✅ 必须 | 打该渠道包所用的分支名，如 `<渠道>` 分支 |

> 运行打包时可在 `workflow_dispatch` 的 input 临时覆盖 `gitee_repo` / `gitee_branch`（留空则用此 Secret）。

### iOS 签名（**按渠道**，build-ios.yml 必填）

> 各渠道可能属于不同公司，Apple Developer 账号 / 证书 / 描述文件 / Team ID 均不同，因此签名凭据必须按渠道独立配置，命名规则：`<凭据名>_<渠道大写>`。工作流通过 `secrets[format('IOS_..._{0}', inputs.oem_channel)]` 动态拼接。

| Secret 名 | 用途 | 必需 | 取值说明 |
|---|---|---|---|
| `IOS_P12_BASE64_<渠道大写>` | 该渠道分发证书 .p12 的 base64 | ✅ 必须 | 该渠道公司的证书：`base64 -i distribution.p12 \| pbcopy` |
| `IOS_P12_PASSWORD_<渠道大写>` | 该 .p12 导出密码 | ✅ 必须 | 证书导出时设置的密码 |
| `IOS_MOBILEPROVISION_BASE64_<渠道大写>` | 该渠道 App Store 分发描述文件 base64 | ✅ 必须 | `base64 -i AppStore.mobileprovision \| pbcopy`；bundleId 须匹配该渠道，profileSpecifier 须匹配该渠道 `oem.json` 的 `ios.profileSpecifier` |
| `IOS_TEAM_ID_<渠道大写>` | 该渠道 Apple Developer Team ID | ✅ 必须 | 与该渠道证书/描述文件同团队（Membership → Team ID） |
| `IOS_ADHOC_PROVISION_BASE64_<渠道大写>` | 该渠道 Ad Hoc 描述文件 base64 | ⚪ 可选 | 仅该渠道 `build_adhoc=true` 时需要 |

### App Store Connect 上传（**按渠道**，upload_to_asc=true 时）

> ASC API Key 属于对应公司/团队的 ASC 账号，同样按渠道命名。

| Secret 名 | 用途 | 必需 | 取值说明 |
|---|---|---|---|
| `ASC_API_KEY_ID_<渠道大写>` | 该渠道 ASC API Key ID | ✅* | *仅该渠道自动上传 ASC 时必填 |
| `ASC_ISSUER_ID_<渠道大写>` | 该渠道 ASC Issuer ID | ✅* | 同上 |
| `ASC_API_KEY_P8_<渠道大写>` | 该渠道 API Key 的 .p8 文件全文 | ✅* | `cat AuthKey_<ID>.p8`（含 BEGIN/END 行），须与 API Key ID 对应 |

> 工作流用 `secrets[format('ASC_API_KEY_ID_{0}', inputs.oem_channel)]` 等动态拼接。未配某渠道的 ASC Secret 时，该渠道需将 `upload_to_asc` 设为 `false` 跳过上传。

### DCloud appkey（按渠道，打包必填）

| Secret 名 | 用途 | 取值说明 |
|---|---|---|
| `DLOUD_APPKEY_<渠道大写>` | 该渠道 DCloud iOS appkey | DCloud 控制台对应 appid 下发的 iOS appkey |

> 工作流用 `secrets[format('DLOUD_APPKEY_{0}', inputs.oem_channel)]` 动态拼接，工作流中不写死任何渠道名。

### 渠道 bundleId（仅 diagnose 诊断用，可选）

| Secret 名 | 用途 | 说明 |
|---|---|---|
| `IOS_BUNDLE_ID_<渠道大写>` | 该渠道 iOS bundleId | = 该渠道 Android applicationId |

> `build-ios` / `prepare-ios-project` 的 bundleId 运行时从 Gitee 源码 `oem_config/<渠道>/oem.json` 动态读取，**无需**配这些 Secret；仅 `diagnose-asc.yml`（不克隆 Gitee）需要。

## 配置命令

使用已登录本仓库账号的 `gh` CLI 配置（**推荐从文件/stdin 读取，避免值进 shell 历史**）。按渠道的 Secret 以 shell 变量 `CH=<渠道大写>` 配置，每个渠道重跑一次（改 `CH` 即可）：

```bash
# ---- Gitee 源码访问（全局，只配一次）----
# 文本类：从临时文件读（配完删除文件）
printf '%s' 'git@gitee.com:<组织>/<仓>.git' > /tmp/.s_repo   && gh secret set GITEE_REPO  < /tmp/.s_repo   --repo ling870312/merchant_work && rm -f /tmp/.s_repo
printf '%s' '<分支>'                        > /tmp/.s_branch && gh secret set GITEE_BRANCH < /tmp/.s_branch --repo ling870312/merchant_work && rm -f /tmp/.s_branch

# 私钥：直接从本地文件读
gh secret set GITEE_SSH_KEY < ~/.ssh/gitee_deploy_key --repo ling870312/merchant_work

# ---- 每渠道一套：改 CH 后重跑（签名 / appkey / ASC / bundleId）----
CH=<渠道大写>

# 证书 / 描述文件：管道生成 base64 后直接灌入 Secret（不落盘文件）
base64 -i distribution.p12               | gh secret set "IOS_P12_BASE64_${CH}"           --repo ling870312/merchant_work
base64 -i AppStore.mobileprovision       | gh secret set "IOS_MOBILEPROVISION_BASE64_${CH}" --repo ling870312/merchant_work
# 可选：Ad Hoc 描述文件（仅该渠道 build_adhoc=true 时需要）
base64 -i AdHoc.mobileprovision          | gh secret set "IOS_ADHOC_PROVISION_BASE64_${CH}" --repo ling870312/merchant_work

# .p8 密钥文件：直接从本地文件读
gh secret set "ASC_API_KEY_P8_${CH}" < ~/AuthKey_<ID>.p8 --repo ling870312/merchant_work

# 短文本 / 密码类：交互式（不回显，不进历史）
gh secret set "IOS_P12_PASSWORD_${CH}" --repo ling870312/merchant_work      # 粘贴后回车
gh secret set "IOS_TEAM_ID_${CH}"      --repo ling870312/merchant_work
gh secret set "ASC_API_KEY_ID_${CH}"   --repo ling870312/merchant_work
gh secret set "ASC_ISSUER_ID_${CH}"    --repo ling870312/merchant_work
gh secret set "DLOUD_APPKEY_${CH}"     --repo ling870312/merchant_work
# 仅 diagnose-asc.yml 需要（可选）
gh secret set "IOS_BUNDLE_ID_${CH}"    --repo ling870312/merchant_work

# 查看已配置的 Secret 名（不显示值）
gh secret list --repo ling870312/merchant_work
```

## 安全注意事项

- 所有 `gh secret set` 都通过 stdin / 文件传入，**不要用 `-b '<值>'`**（会进 shell 历史）；
- 配置私钥/证书的临时文件用完即删；
- Gitee 部署私钥应为**只读**且仅授权给本仓所需仓库；
- 各渠道签名、ASC、appkey 凭据按渠道独立，**不要跨渠道混用**；
- 切勿在本仓提交任何明文敏感值（含真实渠道名、包名、证书、私钥、appkey、Gitee 地址）；如误提交，GitHub 后台轮换密钥并清理 git 历史。
