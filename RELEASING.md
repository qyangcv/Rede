两个平台各一条命令发布：

```bash
bash scripts/release-macos.sh
bash scripts/release-ios.sh
```

脚本打开 CloudKit Console 并暂停时：在 `iCloud.dev.qyang.Rede` → Development → Deploy Schema Changes… 部署，回到终端选 Re-check；待部署项里有不想要的字段就选 Abort。
