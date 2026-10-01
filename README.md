<div align="center">

<img src=".asserts/icon.png" width="64" alt="Rede">

# Rede

一款轻量、开源、免费的中文 EPUB 阅读器，支持 macOS 与 iOS，通过 iCloud 双端同步。

![macOS](https://img.shields.io/badge/macOS-26.0+-000?logo=apple&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-26.0+-000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)

</div>

## 预览

![Rede 截图](.asserts/frame-1.png)
![Rede 截图](.asserts/frame-2.png)
![Rede 截图](.asserts/frame-3.png)


## 功能

**书库**

- 导入电子书（EPUB 格式），开始阅读
- 管理、重命名、删除书籍

**阅读**

- macOS：方向键 `←` / `→` 翻页，单双栏视图自动切换
- iPhone：点击屏幕两侧或左右滑动翻页，下滑返回书库
- 阅读进度自动保存

**样式**

- 选择字体、调节字号与字体粗细
- 调整行距、段距
- 切换深色模式、浅色模式
- 切换背景色、背景图案

**iCloud 同步**

- 在登录同一 Apple ID 的设备之间同步书籍、书籍信息和阅读进度
- 默认关闭，需要在设置中手动开启，重启 App 后生效

**检查更新**

- macOS：菜单栏 “Rede > 检查更新”

## 安装

**macOS**

> 需要 macOS 版本 >= 26.0

1. 从 [Releases](https://github.com/qyangcv/Rede/releases/latest) 下载最新的 `Rede.dmg`
2. 打开 dmg，将 Rede 拖入 “应用程序” 文件夹

**iOS (审核中，即将开放...)** 

> 需要 iOS 版本 >= 26.0

1. 在 App Store 安装 [TestFlight](https://apps.apple.com/app/testflight/id899247664)
2. 在 iOS 上打开 [TestFlight 公开链接](https://testflight.apple.com/join/UvDG6ykV)，接受邀请并安装 Rede 

## 使用的开源工具

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [ReadiumCSS](https://github.com/readium/css)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Kanna](https://github.com/tid-kijyun/Kanna)
