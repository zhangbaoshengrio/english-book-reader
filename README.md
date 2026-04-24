# English Book Reader

[English](#english) | [中文](#中文)

---

## English

A Flutter-based Android app for reading English books with built-in dictionary lookup, vocabulary management, and study tools.

### Features

**Reading**
- Supports TXT and EPUB formats
- Left/right swipe pagination (default) or continuous vertical scroll
- Adjustable font size, line height, margin, background theme, and font family
- Starred words highlighted with a golden background while reading

**Dictionary Lookup**
- Tap any word to instantly look it up
- Supports MDX, ECDICT (.db), and TSV/CSV dictionary formats
- Multiple dictionaries shown in tabs, freely reorderable
- Download popular dictionaries in-app: Oxford Advanced Learner's 10th (EN-CN), Collins COBUILD 8 (EN-EN), 21st Century English-Chinese, Longman, Macmillan, and more
- Example sentences with Chinese translations extracted directly from the dictionary
- Sentence translation via Google Translate

**Vocabulary**
- Star any definition to save it with auto-filled phonetic, part of speech, English definition, and Chinese translation
- Edit saved entries: phonetic, POS, definition, translation, example sentence
- Export vocabulary as Anki deck (.apkg), PDF, detailed TXT, or word list TXT
- JSON backup and restore (safe across reinstalls)

**Navigation**
- Swipe down to add a bookmark on the current page
- Swipe up to close the book and return to the shelf
- Table of contents / bookmarks / notes panel (tap the 📖 icon in the toolbar)
- Notes are saved per book and page, with jump-to-page support

### Download

Download the latest APK from the [Releases](https://github.com/zhangbaoshengrio/english-book-reader/releases) page.

> Requires Android 7.0+. Allow installation from unknown sources when prompted.

### Build from Source

```bash
flutter pub get
flutter run --release
```

Requires Flutter 3.x and Android SDK.

### Dictionary Sources

Dictionaries are not bundled with the app. You can:
- Download them directly from the in-app Dictionary Manager (tap the gear icon while reading, or via Settings)
- Import your own `.mdx`, `.db` (ECDICT), or `.tsv` / `.csv` files

---

## 中文

一款基于 Flutter 的 Android 英文书籍阅读器，集成词典查词、生词本管理和学习工具。

### 功能介绍

**阅读**
- 支持 TXT 和 EPUB 格式
- 左右翻页（默认）或上下连续滚动，可在设置中切换
- 可调节字号、行距、页边距、背景主题、字体
- 已收藏单词在正文中以姜黄色背景高亮显示

**查词**
- 点击任意单词即时查词
- 支持 MDX、ECDICT (.db)、TSV/CSV 格式词典
- 多本词典以 tab 形式展示，可自由排序
- 应用内直接下载常用词典：牛津高阶第10版英汉双解、柯林斯8英英、21世纪英汉、朗文、麦克米伦等
- 例句中文翻译直接从词典提取，无需网络
- 支持整句 Google 翻译

**生词本**
- 星标任意释义，自动填入音标、词性、英文定义、中文翻译
- 可编辑词条：音标、词性、定义、翻译、例句
- 导出为 Anki 卡组（.apkg）、PDF、详细 TXT、单词列表 TXT
- JSON 备份与恢复（重装应用后可完整还原）

**导航**
- 下拉添加当前页书签
- 上拉关闭书籍返回书架
- 目录 / 书签 / 笔记面板（点击阅读器工具栏 📖 图标）
- 笔记按书籍和页码保存，支持一键跳转

### 下载安装

前往 [Releases 页面](https://github.com/zhangbaoshengrio/english-book-reader/releases) 下载最新 APK。

> 需要 Android 7.0 及以上系统。安装时请允许"安装未知来源应用"。

### 自行编译

```bash
flutter pub get
flutter run --release
```

需要 Flutter 3.x 和 Android SDK。

### 词典说明

词典文件不随应用打包，可通过以下方式添加：
- 在应用内「词典管理」页面直接下载（进入阅读器后点击齿轮图标，或通过设置进入）
- 导入自己的 `.mdx`、`.db`（ECDICT）或 `.tsv` / `.csv` 文件
