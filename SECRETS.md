# GitHub Secrets 配置清单

本仓为公开工程仓，所有敏感信息通过 GitHub Secrets 注入。下表为完整清单，按需配置。

## Secret 清单

### Gitee 源码访问

| Secret 名 | 用途 | 必需 | 取值示例 / 获取方式 |
|---|---|---|---|
| `GITEE_SSH_KEY` | Gitee 仓库部署私钥（只读，ed25519），CI 浅克隆源码 | ✅ 必须 | Gitee 仓库「部署公钥」对应的私钥全文（含 BEGIN/END 行） |
| `GITEE_REPO` | Gitee 仓库 SSH 地址 | ✅ 必须 | `git@gitee.com:<组织>/<仓>.git` |
| `GITEE_BRANCH` | Gitee 要克隆的分支 | ✅ 必须 | 如 `laiyima_002` |

> 运行打包时可在 `workflow_dispatch` 的 input 临时覆盖 `gitee_repo` / `gitee_branch`（留空则用此 Secret）。

### iOS 签名

| Secret 名 | 用途 | 必需 | 取值说明 |
|---|---|---|---|
| `IOS_P12_BASE64` | iOS 分发证书 .p12 的 base64 | ✅ 必须 | `base64 -i distribution.p12 \| pbcopy` |
| `IOS_P12_PASSWORD` | .p12 导出密码 | ✅ 必须 | 证书导出时设置的密码 |
| `IOS_MOBILEPROVISION_BASE64` | App Store 分发描述文件 base64 | ✅ 必须 | `base64 -i AppStore.mobileprovision \| pbcopy` |
| `IOS_ADHOC_PROVISION_BASE64` | Ad Hoc 描述文件 base64 | ⚪ 可选 | 仅 `build_adhoc=true` 时需要 |
| `IOS_TEAM_ID` | Apple Developer Team ID | ✅ 必须 | 开发者后台 Membership → Team ID（如 `ABCD123XYZ`） |

### App Store Connect 上传（upload_to_asc=true 时）

| Secret 名 | 用途 | 必需 | 取值说明 |
|---|---|---|---|
| `ASC_API_KEY_ID` | App Store Connect API Key ID | ✅* | *仅自动上传 ASC 时必填 |
| `ASC_ISSUER_ID` | ASC Issuer ID | ✅* | 同上 |
| `ASC_API_KEY_P8` | API Key 的 .p8 文件全文 | ✅* | `cat AuthKey_<ID>.p8`（含 BEGIN/END 行） |

### DCloud appkey（按渠道，打包必填）

| Secret 名 | 渠道 | 取值说明 |
|---|---|---|
| `DLOUD_APPKEY_LAIYIMA` | 来一码 | DCloud 控制台对应 appid 下发的 iOS appkey |
| `DLOUD_APPKEY_RONGYIFU` | 融易付 | 同上 |
| `DLOUD_APPKEY_XINGLIANYUN` | 湾驱智联云 | 同上 |

> 工作流按 `oem_channel` 转大写后间接引用 `DLOUD_APPKEY_<CHANNEL>`，故 Secret 名必须全大写渠道码。

### 渠道 bundleId（仅 diagnose 诊断用，可选）

| Secret 名 | 渠道 | 说明 |
|---|---|---|
| `IOS_BUNDLE_ID_LAIYIMA` | 来一码 | iOS bundleId（= Android applicationId） |
| `IOS_BUNDLE_ID_RONGYIFU` | 融易付 | 同上 |
| `IOS_BUNDLE_ID_XINGLIANYUN` | 湾驱智联云 | 同上 |

> `build-ios` / `prepare-ios-project` 的 bundleId 运行时从 Gitee 源码 `oem_config/<channel>/oem.json` 动态读取，**无需**配这些 Secret；仅 `diagnose-asc.yml`（不克隆 Gitee）需要。

## 配置命令

使用已登录 `ling870312` 的 `gh` CLI 配置（**推荐从文件/stdin 读取，避免值进 shell 历史**）：

```bash
# 文本类：从临时文件读（配完删除文件）
printf '%s' 'git@gitee.com:<组织>/<仓>.git' > /tmp/.s_repo   && gh secret set GITEE_REPO  < /tmp/.s_repo   --repo ling870312/merchant_work && rm -f /tmp/.s_repo
printf '%s' 'laiyima_002'                   > /tmp/.s_branch && gh secret set GITEE_BRANCH < /tmp/.s_branch --repo ling870312/merchant_work && rm -f /tmp/.s_branch

# 私钥 / 证书：直接从本地文件读
gh secret set GITEE_SSH_KEY            < ~/.ssh/gitee_deploy_key          --repo ling870312/merchant_work
gh secret set ASC_API_KEY_P8          < ~/AuthKey_XXXXXXXXXX.p8          --repo ling870312/merchant_work

# base64 类：管道生成后直接灌入 Secret（不落盘文件）
base64 -i distribution.p12            | gh secret set IOS_P12_BASE64          --repo ling870312/merchant_work
base64 -i AppStore.mobileprovision    | gh secret set IOS_MOBILEPROVISION_BASE64 --repo ling870312/merchant_work

# 短文本 / 密码类：交互式（不回显，不进历史）
gh secret set IOS_P12_PASSWORD       --repo ling870312/merchant_work      # 粘贴后回车
gh secret set IOS_TEAM_ID            --repo ling870312/merchant_work
gh secret set ASC_API_KEY_ID         --repo ling870312/merchant_work
gh secret set ASC_ISSUER_ID          --repo ling870312/merchant_work
gh secret set DLOUD_APPKEY_LAIYIMA   --repo ling870312/merchant_work
gh secret set DLOUD_APPKEY_RONGYIFU  --repo ling870312/merchant_work
gh secret set DLOUD_APPKEY_XINGLIANYUN --repo ling870312/merchant_work
gh secret set IOS_BUNDLE_ID_LAIYIMA  --repo ling870312/merchant_work
gh secret set IOS_BUNDLE_ID_RONGYIFU --repo ling870312/merchant_work
gh secret set IOS_BUNDLE_ID_XINGLIANYUN --repo ling870312/merchant_work

# 查看已配置的 Secret 名（不显示值）
gh secret list --repo ling870312/merchant_work
```

## 安全注意事项

- 所有 `gh secret set` 都通过 stdin / 文件传入，**不要用 `-b '<值>'`**（会进 shell 历史）；
- 配置私钥/证书的临时文件用完即删；
- Gitee 部署私钥应为**只读**且仅授权给本仓所需仓库；
- 切勿在本仓提交任何明文敏感值；如误提交，GitHub 后台轮换密钥并清理 git 历史。
