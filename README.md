<div align="center">

<img src=".asserts/icon.png" width="64" alt="MyReader">

# MyReader

一个轻量的 macOS 原生中文阅读器，仅用 2500 行代码实现。 

![macOS](https://img.shields.io/badge/macOS-26.0+-000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)

</div>

![MyReader 截图](.asserts/screenshot.png)

## 功能

**书库**

- 导入电子书（EPUB 格式），开始阅读
- 管理、重命名、删除书籍


**阅读**

- `←` / `→` 翻页
- 阅读进度自动保存

**样式**

- 切换字体、调节字号与粗细
- 调整行距、段距
- 切换背景色、背景图案

<!-- ## 构建

需要 Xcode 26 与 macOS 26。

```bash
git clone <repo-url> MyReader
open MyReader/MyReader.xcodeproj
```

> Debug 构建会把书库写在仓库根目录的 `.library/` 下，方便调试；Release 构建使用 `~/Library/Application Support/MyReader/`。 -->

<!-- ## 实现

```
MyReader/
├── Epub/        EPUB 解析：container → OPF → spine / manifest / nav·NCX
├── Library/     书库：SwiftData 存储、导入与删除
└── Reader/      阅读器：WKWebView 容器、JS 桥接、样式与进度
    └── Web/     排版外壳页与 ReadiumCSS
``` -->

<!-- 几点设计上的取舍：

- **不解压到磁盘。** EPUB 保持原样存放，WebView 通过自定义的 `epub://` scheme 按需从压缩包中读取资源。
- **排版交给 CSS。** 正文样式基于 [ReadiumCSS](https://github.com/readium/css)，分页依靠 CSS 多栏布局完成，JS 只负责导航、锚点和进度。
- **进度按字符偏移记录。** 保存的是当前页首字符在章节文本中的位置，而不是页码，调整字号或窗口大小后依然能回到同一段落。 -->

## 技术栈

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [ReadiumCSS](https://github.com/readium/css)
