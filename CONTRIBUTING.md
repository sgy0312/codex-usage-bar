# Contributing

欢迎通过 Issue 或 Pull Request 改进 Codex Usage Bar。

## 本地验证

修改前请确保系统已安装 Apple Command Line Tools。提交前运行：

```sh
make check
```

该命令会构建应用、校验 `Info.plist`，并运行内置数据解析自检。

## 提交范围

- 保持应用为原生 macOS 菜单栏工具。
- 不在源码、日志或测试数据中加入访问令牌及账户凭据。
- 修改用量接口解析时，同时更新 `--self-test` 覆盖的示例数据。
- UI 调整后同步更新 `docs/ui-preview.png` 和 `docs/ui-preview.svg`。
