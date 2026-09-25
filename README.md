<div align="center">

<img src=".asserts/icon.png" width="64" alt="Rede">

# Rede

一个轻量的 macOS 原生中文阅读器，仅用 2500 行代码实现。 

![macOS](https://img.shields.io/badge/macOS-26.0+-000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)

</div>

![Rede 截图](.asserts/screenshot.png)

## 功能

**书库**

- 导入电子书（EPUB 格式），开始阅读
- 管理、重命名、删除书籍

**阅读**

- 方向键 `←` / `→` 翻页
- 单双栏视图自动切换
- 阅读进度自动保存

**样式**

- 选择字体、调节字号与字体粗细
- 调整行距、段距
- 切换背景色、背景图案

**检查更新**

- 菜单栏 “Rede > 检查更新”

## 安装

1. 从 [Releases](https://github.com/qyangcv/Rede/releases/latest) 下载最新的 `Rede.dmg`
2. 打开 dmg，将 Rede 拖入 “应用程序” 文件夹
3. 首次打开时会被系统拦截，前往 “系统设置 > 隐私与安全性 > 安全性”，找到 “已阻止 Rede.app 以保护 Mac”，点击“仍要打开”

> Rede 未经 Apple 公证，也可以在终端执行 `xattr -dr com.apple.quarantine /Applications/Rede.app` 代替第 3 步

## 使用的开源工具

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [ReadiumCSS](https://github.com/readium/css)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
