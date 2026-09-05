# GitHub Secrets 配置清单

本仓为公开工程仓，敏感值只经 GitHub Secrets 注入。文档使用占位符：

- `<渠道>`：`workflow_dispatch` 的 `oem_channel` 输入值（小写渠道码）
- `<渠道大写>`：渠道码大写形式（Secret 名不区分大小写，统一大写）
- `<组织>` / `<仓>` / `<分支>`：私有源码仓的地址与分支

## 必配清单

| Secret | 用途 | 必需 |
|---|---|---|
| `GITEE_SSH_KEY` | 私有源码仓部署私钥（只读，ed25519） | ✅ |
| `GITEE_REPO` | 私有源码仓 SSH 地址（`git@gitee.com:<组织>/<仓>.git`） | ✅ |
| `GITEE_BRANCH` | 打包所用源码分支 | ✅ |
| `ASSET_PAT` | 私有资产仓 PAT（Contents 读写；build 仅需读） | ✅ |
| `DLOUD_APPKEY_<渠道大写>` | DCloud 控制台对应 appid 下发的 iOS appkey | ✅（每渠道） |
| `IOS_P12_BASE64_<渠道大写>` | 该渠道分发证书 .p12 的 base64 | ✅（每渠道） |
| `IOS_P12_PASSWORD_<渠道大写>` | 该 .p12 导出密码 | ✅（每渠道） |
| `IOS_MOBILEPROVISION_BASE64_<渠道大写>` | 该渠道 App Store 描述文件 base64（bundleId / profileSpecifier 须与 `oem.json` 一致） | ✅（每渠道） |
| `IOS_TEAM_ID_<渠道大写>` | 该渠道 Apple Developer Team ID | ✅（每渠道） |
| `ASC_API_KEY_ID_<渠道大写>` | 该渠道 ASC API Key ID | ⚪ `upload_to_asc=true` 时 |
| `ASC_ISSUER_ID_<渠道大写>` | 该渠道 ASC Issuer ID | ⚪ 同上 |
| `ASC_API_KEY_P8_<渠道大写>` | 该渠道 ASC API Key 文件全文 | ⚪ 同上 |
| `IOS_ADHOC_PROVISION_BASE64_<渠道大写>` | 该渠道 Ad Hoc 描述文件 base64 | ⚪ `build_adhoc=true` 时 |
| `IOS_BUNDLE_ID_<渠道大写>` | 该渠道 iOS bundleId | ⚪ 仅 `diagnose-asc` 用 |

> 工作流按 `secrets[format('<前缀>_{0}', inputs.oem_channel)]` 动态拼接 Secret 名，命名须与 `oem_channel` 对应。各渠道可能分属不同公司 / Apple 账号，**凭据按渠道独立，勿混用**。

## 配置命令（示例）

```bash
REPO=<公开仓 full_name>

# 私有源码仓访问（全局，一次）
printf '%s' 'git@gitee.com:<组织>/<仓>.git' | gh secret set GITEE_REPO    --repo "$REPO"
printf '%s' '<分支>'                        | gh secret set GITEE_BRANCH --repo "$REPO"
gh secret set GITEE_SSH_KEY < ~/.ssh/gitee_deploy_key --repo "$REPO"

# 私有资产仓 PAT
gh secret set ASSET_PAT < /tmp/.asset_pat --repo "$REPO" && rm -f /tmp/.asset_pat

# 每渠道一套：改 CH 重跑
CH=<渠道大写>
base64 -i distribution.p12         | gh secret set "IOS_P12_BASE64_${CH}"           --repo "$REPO"
base64 -i AppStore.mobileprovision | gh secret set "IOS_MOBILEPROVISION_BASE64_${CH}" --repo "$REPO"
gh secret set "IOS_P12_PASSWORD_${CH}" --repo "$REPO"      # 交互式粘贴，不回显
gh secret set "IOS_TEAM_ID_${CH}"      --repo "$REPO"
gh secret set "DLOUD_APPKEY_${CH}"     --repo "$REPO"
gh secret set "ASC_API_KEY_ID_${CH}"   --repo "$REPO"
gh secret set "ASC_ISSUER_ID_${CH}"    --repo "$REPO"
gh secret set "ASC_API_KEY_P8_${CH}"   < ~/AuthKey_<ID>.p8 --repo "$REPO"
# 可选：ad-hoc / 诊断
gh secret set "IOS_ADHOC_PROVISION_BASE64_${CH}" --repo "$REPO"
gh secret set "IOS_BUNDLE_ID_${CH}"              --repo "$REPO"

gh secret list --repo "$REPO"   # 仅显示 Secret 名
```

## 注意事项

- 所有 `gh secret set` 通过 stdin / 文件传入，**勿用 `-b '<值>'`**（会进 shell 历史）；私钥 / 证书临时文件用完即删；
- Gitee 部署私钥应为**只读**且仅授权打包所需仓库；`ASSET_PAT` 用 fine-grained PAT 仅授权资产仓，设置短有效期;
- 严禁在本仓提交任何明文敏感值（含真实渠道名、包名、证书、私有仓地址）；如误提交，立即轮换密钥并清理历史。
