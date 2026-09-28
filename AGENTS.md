# AGENTS.md

本文件为 AI 编码代理提供 Codex Usage Bar 仓库的导航指南。

## 仓库结构

- `Sources/CodexUsageBar/main.swift`：全部 Swift 源码（单文件菜单栏应用）
- `Resources/Info.plist`：应用元数据
- `docs/`：UI 预览（`ui-preview.png` / `ui-preview.svg`）与架构说明（`ARCHITECTURE.md`）
- `build.sh` / `install.sh`：构建与安装脚本
- `Makefile`：常用开发命令
- `CHANGELOG.md`：版本记录
- `CONTRIBUTING.md`：贡献指南

## 开发约定

- 原生 macOS 菜单栏应用，目标系统 macOS 13+
- 数据来源：本机 Codex 只读 `account/rateLimits/read` 接口
- 不读取、复制或保存登录令牌
- 提交前运行 `make check`（构建 + Info.plist 校验 + 内置自检）
- UI 调整后同步更新 `docs/ui-preview.png` 与 `docs/ui-preview.svg`
- 修改用量接口解析时同步更新 `--self-test` 覆盖的示例数据

## 禁止事项

- 不得在源码、日志或测试数据中加入访问令牌及账户凭据
- 不得破坏 `Sources/` 源码与 `build.sh`/`install.sh`/`Makefile` 的既有功能
- 不得改写仓库 git 历史（禁止 rebase / filter-branch / force push）