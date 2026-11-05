# Xmind 快捷样式槽（Style Slots）

> 5 个可复用的样式槽，一键套用/保存颜色 + 加粗 + 字号，Xmind 原生插件 + macOS 液态玻璃悬浮面板。

## 效果

- **⌃⌥ 1~5**：一键把选中的样式槽套用到 Xmind 当前主题（或选中的文字片段）
- **⌃⌥⇧ 1~5**：把当前主题/选中文字的样式（颜色、加粗、字号）保存到对应槽位
- **悬浮面板**：macOS 原生液态玻璃（macOS 26 NSGlassEffectView），跟随 Xmind 自动启动，可拖动、可缩放
- **文字级格式**：在 Xmind 里选中一段文字后再「保存样式」，会精确记录那段文字的格式；之后点击面板对应槽位，只把格式套用到这段选中的文字上

支持 macOS 13+，Apple Silicon (arm64) 和 Intel (x86_64)。

---

## 安装

### 方式 A：一键脚本（推荐）

需要有 Xcode Command Line Tools（`swiftc`）。脚本会自动下载 Node.js、安装 asar、解包你机器上的 Xmind app.asar、注入并重打包。

```bash
# clone
git clone https://github.com/<你的用户名>/xmind-style-slots.git
cd xmind-style-slots

# 执行安装
bash plugin/install.sh
```

需要首次运行授予终端对 Xmind 的读写权限（脚本会自动关闭 Xmind 替换 `app.asar`）。

### 方式 B：只用预编译面板 + 手动注入

如果你有 **GitHub Release** 里的预编译 `XmindStylePanel-macos-universal.tar.gz`：

```bash
tar -xzf XmindStylePanel-macos-universal.tar.gz -C ~/Applications/
# 面板装好了，但还需要把插件注入到 Xmind：
bash plugin/install.sh
```

实际上 `install.sh` 也会自己编译面板，所以通常用方式 A 即可。

### 安装了什么？

| 位置 | 作用 |
|---|---|
| `/Applications/Xmind.app/Contents/Resources/app.asar` | 注入了样式槽 JS 的替换版本（原文件备份在 `tools/app.asar.bak`） |
| `~/Applications/Xmind 样式槽.app` | 悬浮面板（LSUIElement，不在 Dock 显示，菜单栏也没有） |
| `Xmind → hook.js` | 开放本机调试端口 127.0.0.1:9222，并让面板跟随 Xmind 启动/退出 |

## 使用

### 快捷键（在 Xmind 编辑时）

| 快捷键 | 动作 |
|---|---|
| ⌃⌥ 1~5 | 套用样式槽 1~5 |
| ⌃⌥⇧ 1~5 | 保存当前样式到槽 1~5 |

### 文字级精度

1. 在 Xmind 里双击某个主题进入文字编辑
2. **选中一段文字**（鼠标划过）
3. 按 **⌃⌥⇧ 1**（或其他槽位）保存 → 保存的是这段文字的精确格式
4. 之后在另一个主题里选中一段文字再按 **⌃⌥ 1**，样式只套用到那段文字上

不选文字时，保存/套用的是整个主题的格式。

### 悬浮面板

面板显示 5 个槽位，实时反映已保存的颜色/加粗/字号：

- **点槽位** = 套用样式（等价于快捷键 ⌃⌥ 1~5）
- **长按槽位的「保存」按钮** = 保存样式（等价于 ⌃⌥⇧ 1~5）
- **底部提示**：显示当前 Xmind 是否连接成功、是否选中了文字

窗口可拖动、可右下角缩放，位置/尺寸会被 macOS 记住。

---

## 卸载

```bash
bash plugin/uninstall.sh
```

会还原原始 `app.asar` 并移除 `~/Applications/Xmind 样式槽.app`。

> 原始备份在 `tools/app.asar.bak`（首次安装时自动生成）。如果这个文件丢了，请通过 Xmind 官方渠道重新安装来还原。

---

## 目录结构

```
.
├── plugin/
│   ├── xmind-style-slots.js   # 注入到 Xmind 的插件本体
│   ├── install.sh             # 一键安装（自举 node/asar/解包/注入/打包/面板）
│   └── uninstall.sh           # 还原原始 app.asar
├── panel/
│   ├── main.swift             # 原生 Swift 悬浮面板
│   ├── index.html             # 面板 UI
│   ├── Info.plist             # app bundle 配置
│   └── build.sh               # 编译面板（arm64 + x86_64 通用二进制）
├── tools/
│   ├── package.json           # asar 依赖声明
│   ├── cdp.js                 # 本地 CDP 调试脚本（开发用）
│   └── package-release.sh     # 打预编译 release 包
└── .gitignore
```

## 开发说明

### 插件怎么工作的？

- 在 Xmind 的 Electron 主进程里，`hook.js` 追加 `remote-debugging-port=9222`（只监听 127.0.0.1）
- `plugin/xmind-style-slots.js` 被追加到 `renderer/editor.js` 末尾，注入 `window.__xmindStyleSlots`
- 悬浮面板用 CDP WebSocket 连接 `127.0.0.1:9222/json/list`，找到 editor page，然后 `Runtime.evaluate` 调用 `window.__xmindStyleSlots.info() / apply() / save()`

### 调试面板

面板日志写到 `/tmp/xmind-style-panel.log`：

```bash
tail -f /tmp/xmind-style-panel.log
```

### 重新编译面板

```bash
bash panel/build.sh
```

### 打包 Release

```bash
bash tools/package-release.sh
# 产物: release/XmindStylePanel-macos-universal.tar.gz
```

## 常见问题

**Q: 点了 Xmind 编辑区域后，样式面板要点两下才能生效？**
macOS 默认非活动窗口需要两次点击才能激活。本项目用运行时 patch（`acceptsFirstMouse` 返回 true）解决了这个问题 —— 面板启动后会自动对 WKWebView 内部的私有视图打补丁。

**Q: Xmind 更新了之后样式面板还能用吗？**
Xmind 的 `app.asar` 会被版本覆盖。更新 Xmind 后需要重新跑一次 `bash plugin/install.sh`。

**Q: 面板不显示 / 一直显示「未连接」？**
确认 Xmind 是通过 `install.sh` 安装了插件的版本（hook.js 里有 remote-debugging-port）。也可以手动打开：`osascript -e 'tell application "Xmind" to activate'`。然后看一下 `/tmp/xmind-style-panel.log`。

**Q: 可以加更多样式槽吗？**
在 `plugin/xmind-style-slots.js` 顶部改 `CONFIG.slotCount`，然后重装。

## License

MIT
