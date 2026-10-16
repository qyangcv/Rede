# 发布

macOS 与 iOS 各一条命令，脚本会在打包前校验云端 schema：

```bash
bash scripts/release-macos.sh
bash scripts/release-ios.sh
```

首次发布前一次性把 CloudKit 管理 token 存进 Keychain（CloudKit Console → Settings 生成）：

```bash
xcrun cktool save-token --type management
```

## 改动了 Rede/Shared 下的模型 (`@Model`)

模型改动也是云端 schema 改动，必须**先部署再发版**：

1. 用 Debug 构建跑一遍受影响的功能（否则 Development 不会生成新结构）
2. `bash scripts/cloudkit-schema.sh record`，提交 `cloudkit/schema.ckdb`
3. CloudKit Console → 容器 `iCloud.dev.qyang.Rede` → Schema → Deploy Schema Changes

`bash scripts/cloudkit-schema.sh deploy` 可代替第 2、3 步：导出基线、打开控制台、复核结果。

漏做时发布脚本会在打包前报错中止，并列出缺失的结构。`cktool` 只能写 development 环境，Production 只能在控制台部署。
