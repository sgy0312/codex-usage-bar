# Codex Usage Bar

一个原生 macOS 菜单栏小程序。左侧“5H”圆环显示 5 小时窗口的剩余额度，右侧“1W”圆环显示每周剩余额度；点击圆环可查看精确百分比及重置时间。

圆环颜色：剩余 51% 以上为绿色，21%–50% 为橙色，20% 以下为红色。

![Codex Usage Bar 预览](ui-preview.png)

数据通过本机 Codex 的只读 `account/rateLimits/read` 接口获取。程序不读取、复制或保存登录令牌。

## 运行要求

- macOS 13 或更高版本
- 已安装 ChatGPT/Codex 桌面应用并登录 Codex
- 构建时需要 Apple Command Line Tools

## 构建

```sh
./build.sh
```

构建结果位于 `build/Codex Usage Bar.app`。

## 验证数据

```sh
./build/Codex\ Usage\ Bar.app/Contents/MacOS/CodexUsageBar --print-once
```

离线验证解析逻辑：

```sh
./build/Codex\ Usage\ Bar.app/Contents/MacOS/CodexUsageBar --self-test
```

## 安装并设置登录时启动

```sh
./install.sh
```

应用会安装到 `~/Applications/Codex Usage Bar.app`，登录启动项为
`~/Library/LaunchAgents/local.codex.usagebar.plist`。

菜单栏数据默认每 5 分钟刷新一次。点击“刷新频率”可选择 1、5、10、15 或 30 分钟，设置会自动保存；也可以点击“立即刷新”。
