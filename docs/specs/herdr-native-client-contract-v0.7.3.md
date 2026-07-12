# Herdr Native Client Contract — v0.7.3

日期：2026-07-12

本文件固定 VVTerm Herdr 原生客户端 Spike 的外部契约。后续实现不得仅根据已安装二进制的字符串或面向人的 CLI 输出推断协议。

## 固定基线

- Herdr source tag：`v0.7.3`
- Herdr Git revision：`d0111c9f9022e0ec26d8f03236a91b026b567d45`
- Release archive SHA-256：`86f4ade98e4fa048b99ad59d1453da00b691dcdf559bbd18441f495b448c02fc`
- Binary version：`0.7.3`
- Private client protocol：`16`
- Source license：`AGPL-3.0-or-later`，另提供商业许可证

Revision、archive hash 和协议常量分别由官方 Git tag、Homebrew formula 和 `src/protocol/wire.rs` 核验。

## 完整 Workspace Bridge

v0.7.3 没有公开的 `herdr bridge client --stdio` 命令。当前可用入口是内部命令：

```sh
herdr --session <session> remote-client-bridge
```

该命令：

- 确保远程 Herdr server 正常运行；
- 连接远程 `herdr-client.sock`；
- 将 stdin 原样复制到 client socket；
- 将 client socket 原样复制到 stdout；
- stdin EOF 时对 socket 执行 write half-close；
- 不自行解释、封装或重新编码协议帧。

因此 stdout 是私有 client protocol 的透明字节流，stderr 承载 SSH/CLI 诊断。VVTerm 必须通过无 PTY Exec Stream 启动它，并始终分离 stdout/stderr。

## Private Client Protocol 16

完整 Workspace UI 使用私有协议，而不是 NDJSON：

```text
[4-byte little-endian payload length][bincode 2 standard-config payload]
```

关键约束：

- 普通最大 frame payload：2 MiB；
- Kitty graphics 开启时 server-to-client 最大 payload：32 MiB；
- 首个 client message 必须是 `Hello`；
- 首个 server response 必须是 `Welcome`；
- 版本必须严格等于 16，不提供向后兼容；
- Workspace 客户端请求 `TerminalAnsi`，server 以带单调 `seq`、宽高、`full` 标记和 ANSI bytes 的 `TerminalFrame` 输出；
- SSH read chunk 不等于协议 frame，必须增量重组。

Swift 端不应手写或复制 bincode 2 ABI。Phase 2 仍需从固定 revision 提取最小 Rust client core，并通过窄 C ABI 构建 Apple XCFramework。

## 公开 Terminal Session NDJSON

v0.7.3 提供公开、面向第三方 bridge 的单终端接口：

```sh
herdr --session <session> terminal session observe <target> --cols <n> --rows <n>
herdr --session <session> terminal session control <target> --cols <n> --rows <n> [--takeover]
```

stdout 每行一条 JSON：

- `terminal.frame`：`seq`、`encoding: "ansi"`、`width`、`height`、`full`、base64 `bytes`；
- `terminal.closed`：可选 `reason`。

control stdin 每行一条 JSON：

- `terminal.input`：`text` 或 base64 `bytes`，两者不能同时出现；
- `terminal.resize`：非零 `cols`、`rows`，可选 cell pixel size；
- `terminal.scroll`：`up`/`down`、非零 `lines`，可选 source/坐标/modifiers；
- `terminal.release`：释放 controller 并结束连接。

一个 terminal 同时只能有一个 writable controller；`--takeover` 会替换现有 owner。observer 不拥有 input、resize、scroll 或 takeover authority。

该接口适合后续单 Pane Observe/Control，也可作为 SSH Exec Stream 的真实 Herdr 诊断链路，但它不能渲染或控制完整 Herdr Workspace UI，不能替代 HerdrClientKit。

## 结构化预检

使用一次性无 PTY Exec 执行：

```sh
herdr --session <session> status --json
```

该 JSON 同时包含 `client`、`server` 和 `update`：

- `client.version`、`client.protocol`、`client.binary`；
- `server.running`、`server.version`、`server.protocol`、`server.compatible`；
- 当前 session 和 server capabilities。

第一版只接受 client version `0.7.3`、client protocol `16`、server running、server version `0.7.3`、server protocol `16`。Binary 缺失和命令失败由 Exec 退出状态映射，不解析面向人的 stderr。

## 授权记录

Herdr 源码为 AGPL-3.0-or-later，并声明可提供商业许可证。当前项目决策是不把许可证评估作为技术 Spike 和 ClientKit 实现的阻塞项；本节仅保留来源事实，不参与后续工程阶段的退出判断。
