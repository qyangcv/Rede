两个平台各一条命令发布，脚本会在打包前自动校验云端 schema（管理 token 需已在 Keychain：`xcrun cktool save-token --type management`）：

```bash
bash scripts/release-macos.sh
bash scripts/release-ios.sh
```

**新增或改动模型（`Rede/Shared` 下的 `@Model` 类或它的存储属性）时，先部署再发版：**

1. 用 Debug 构建（Development 环境）走一遍会写入这些模型的功能。Development 的 recordType/字段是客户端写记录时自动建的，不写就不会出现，`record` 也导不出来。当前模型的最小覆盖：`Book` → 导入/编辑书籍信息/翻页；`BookFile` → 导入书籍；`Annotation` → 加书签、高亮、笔记。
2. `bash scripts/cloudkit-schema.sh record` 重新生成 `cloudkit/schema.ckdb`，再 `git add cloudkit/schema.ckdb && git commit`（把基线记进版本库，不是提交给 CloudKit）。
3. CloudKit Console → 容器 `iCloud.dev.qyang.Rede` → Schema → Deploy Schema Changes。

`bash scripts/cloudkit-schema.sh deploy` 可代替第 2、3 步：导出基线、打开控制台、复核结果。

漏做时发布脚本会在打包前报错中止，并列出缺失的结构。`cktool` 只能写 development 环境，Production 只能在控制台部署。
