# Architecture

## 数据流

```text
Codex Usage Bar
  → 启动本机 codex app-server --stdio
  → initialize
  → account/rateLimits/read
  → 解析 5 小时和每周窗口
  → 更新菜单栏圆环与菜单详情
```

应用每次刷新都会启动一个短生命周期的本机 Codex app-server 进程。请求完成或超时后，子进程会被终止。

## 主要组件

- `UsageRingsView`：绘制 `5H` 和 `1W` 圆环及颜色状态。
- `CodexUsageClient`：查找 Codex 可执行文件、调用 app-server 并解析额度响应。
- `AppDelegate`：创建菜单栏项目、管理刷新计时器和用户偏好。
- 命令行模式：`--self-test` 验证解析逻辑，`--print-once` 读取一次真实数据。

## 数据兼容

解析器优先读取 `rateLimitsByLimitId.codex`，并兼容旧版 `rateLimits` 字段。两个窗口按持续时间排序，较短窗口显示为 `5H`，较长窗口显示为 `1W`。

## 隐私

应用只向本机 Codex 进程发送只读额度请求，不读取或持久化认证令牌。持久化内容仅包括用户选择的刷新间隔。
