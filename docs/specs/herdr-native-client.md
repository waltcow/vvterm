# Herdr 原生客户端集成规格

草案日期：2026-07-12

状态：待评审的实现规格

## 摘要

VVTerm 将通过嵌入一个小型、与传输层无关的 Herdr 客户端库 `HerdrClientKit.xcframework`，并复用现有 libssh2 SSH 栈、以每 Attachment 独立的 SSH 连接承载 Herdr 二进制协议，从而提供原生 Herdr 客户端体验。

iOS 端不应打包并启动完整的 Herdr 命令行程序。嵌入式 Framework 只负责 Herdr 协议帧和客户端状态机；VVTerm 负责 SSH 传输、Apple 平台生命周期、输入路由和 Ghostty 渲染；远程 Herdr 继续持有 Workspace、Agent、进程、PTY、控制权和持久化运行状态。

第一步是完成一个端到端技术 Spike。只有真机 iOS 客户端能够通过无 PTY SSH Exec Stream 完成 Herdr 握手、用 Ghostty 渲染真实 ANSI 帧、发送输入和 resize、断开连接并重连恢复完整画面，才能认为核心方案成立。

## 背景

当前 `Core/SSH/SSHClient.swift` 已有两类 SSH Channel：

- `startShell(...)`：申请 PTY 的长期双向 Channel。
- `execute(...)`：不申请 PTY，但会等待命令结束并一次性返回输出的 Exec Channel。

Herdr 原生协议需要第三种 Channel：

- 不申请 PTY、长期保持、支持双向传输，并分别流式输出 stdout 和 stderr 的 Exec Channel。

Herdr 二进制协议不能经过 PTY。终端 echo、换行转换、控制字符处理和行规整都可能破坏协议帧。通过普通 SSH PTY 运行完整 Herdr TUI 可以作为独立模式或降级方案，但不是本规格定义的原生客户端架构。

## 产品目标

该功能将 VVTerm 变成远程 Herdr Runtime 的原生瘦客户端。

远程服务器是以下状态的唯一事实来源：

- Herdr Named Session
- Workspace、Tab、Pane 和 Agent
- 子进程及真实 PTY
- Scrollback 和渲染状态
- Observer/Controller 控制权
- 客户端断开后的持久化运行状态

VVTerm 负责：

- 服务器选择和 SSH 认证
- 启动远程 stdio bridge
- 传输 Herdr 协议帧
- 展示连接和兼容性状态
- 用 Ghostty 渲染 ANSI 输出
- 处理键盘、粘贴、指针、焦点和 resize 输入
- 处理前后台生命周期和重连

关闭或挂起 VVTerm Attachment 不得终止对应的远程 Herdr Runtime 或 Agent。

## 目标

- 在 iOS 和 macOS App 中嵌入最小 Herdr 客户端库。
- 复用现有 `SSHClient`/libssh2 代码、认证和 Host Verification 流程，不启动本地 `ssh` 或 `herdr` 子进程。
- 每个 Herdr Attachment 使用专用 `SSHClient` 实例和独立 TCP 连接，不与交互式 Terminal、SFTP 或其他 Attachment 共享 SSH Session。
- 通过长期无 PTY SSH Exec Channel 传输 Herdr 协议。
- Herdr 协议逻辑不得进入 `SSHClient`。
- 使用现有 Ghostty 集成渲染服务器生成的 ANSI。
- 支持原始终端输入、resize、detach 和 reconnect。
- 第一版严格固定 VVTerm Framework 与远程 Herdr 的版本。
- 在 `Features/Herdr` 中保持 Feature-first 边界。
- 为传输、状态机、输入和生命周期提供确定性的自动化测试。

## 非目标

- 在 iOS App 中打包和运行完整 Herdr executable。
- 将 Herdr Server、PTY Runtime、CLI、安装器或升级器移植到 iOS。
- 同时兼容多个 Herdr Wire Protocol 版本。
- 自动安装或升级远程 Herdr。
- 在 Swift 中重新实现 Herdr 私有协议。
- 用 PTY 传输嵌入式二进制协议。
- 第一阶段支持 Mosh。
- 承诺 iOS 挂起后 SSH 永久在线。
- 在渲染链路验证前开发原生 SwiftUI Workspace、Pane 或 Agent 管理界面。
- 复用 tmux 的生命周期、清理或持久化语义。
- 让 `TerminalTabManager` 管理 Herdr Attachment。

## 第一版约束

第一版面向版本完全受控的个人部署：

- VVTerm 内置客户端和远程 Herdr binary 来自约定的同一源码 revision。
- 远程服务器已经安装 Herdr。
- 远程目标是可通过标准 SSH 连接的 POSIX Linux 或 macOS 主机。
- Apple 目标只要求 arm64：iOS 真机、Apple Silicon iOS Simulator、macOS arm64。
- 版本不一致时直接拒绝连接并显示明确错误，不进行协议协商。

这些约束只缩小产品范围，不降低传输正确性和生命周期要求。

## 总体架构

```text
VVTerm iOS / macOS
│
├─ SwiftUI Feature Shell
├─ Ghostty Terminal Renderer
├─ HerdrSessionController
│  ├─ HerdrClientKitAdapter
│  ├─ HerdrSSHTransport
│  └─ Attachment 生命周期与 Generation 管理
│
└─ 专用 SSHClient / libssh2（每 Attachment 独立 TCP 连接）
   └─ 长期无 PTY Exec Stream
                │
                │ SSH stdin/stdout 二进制帧
                ▼
远程主机
│
├─ 稳定的 Herdr stdio bridge
├─ Herdr Server / Runtime
│  ├─ Workspace / Tab / Pane
│  ├─ Agent 和 PTY
│  └─ Render 与 Controller 状态
└─ 后续可增加结构化 API bridge
```

### 依赖方向

```text
Herdr UI
    → Herdr Application
        → Herdr Domain
        → Herdr Infrastructure
            → Core/SSH
            → HerdrClientKit
```

`Core/SSH` 只暴露通用字节流，不得导入或理解 Herdr 消息。`HerdrClientKit` 不得依赖 SSH、SwiftUI、Ghostty、UIKit、AppKit、Keychain 或 CloudKit。

## Herdr 源码拆分

不要为了 iOS 给完整 Herdr crate 大量增加条件编译。应提取一个小型客户端边界。

建议在 Herdr 仓库中拆分为：

```text
crates/
├─ herdr-protocol/
│  ├─ Client/Server Wire Message
│  ├─ Length Framing
│  └─ Protocol Version
├─ herdr-client-core/
│  ├─ Handshake State
│  ├─ Incremental Decoder
│  ├─ Outbound Queue
│  ├─ Client Event Queue
│  └─ Input / Resize / Attach / Detach
└─ herdr-apple/
   ├─ C ABI Handle 和 DTO
   ├─ Buffer 所有权接口
   └─ Apple Static Library 打包
```

### `herdr-protocol`

只负责可序列化的协议类型和 framing，不得依赖终端生命周期、进程管理、Unix Socket、SSH、PTY 或 UI 库。

### `herdr-client-core`

这是一个与传输层无关的状态机。推荐使用 push/pull，而不是 Rust 回调 Swift：

```rust
client.receive_network_bytes(bytes);
client.take_outbound_bytes();
client.next_event();
client.send_input(bytes);
client.resize(cols, rows);
```

第一阶段只暴露以下事件：

```text
connected
ansi_frame
window_title
protocol_mismatch
server_shutdown
protocol_error
```

Clipboard、Notification、Graphics、Agent 结构化数据和指针事件应在基础链路稳定后再增加。

### `herdr-apple`

该 crate 暴露窄 C ABI，负责 opaque handle、buffer 分配和释放，以及 C-safe DTO 与 Rust 类型之间的转换。

C ABI 必须明确：

- 每个 buffer 由哪一侧分配和释放
- 返回指针是 borrowed 还是 owned
- handle 能否跨线程使用
- error 如何读取和释放
- close 后调用 API 的行为

Rust panic 不得跨越 C ABI unwind。

### 构建产物

编译以下 Static Library：

- `aarch64-apple-ios`
- `aarch64-apple-ios-sim`
- `aarch64-apple-darwin`

最终打包为：

```text
Vendor/HerdrClientKit/HerdrClientKit.xcframework
```

构建流程必须基于固定的 Herdr revision，并向 Swift 暴露内置的 Herdr Version 和 Protocol Version。

## 通用 SSH Exec Stream

### 连接归属

每个 Herdr Attachment 创建并独占一个专用 `SSHClient` 实例，即一条独立的 TCP/SSH 连接。该连接复用现有的认证、Host Verification 和连接建立代码，但不与用户交互式 Terminal、SFTP 或其他 Attachment 共享 Session。

选择独立连接是为了消除特殊情况：Herdr Full Redraw 洪峰与交互式键入不再竞争同一 Socket 和同一 Actor，跨用途公平性调度机制随之不再需要。代价是每个 Attachment 多一次认证握手，在第一版个人部署场景下可以接受。

版本预检应在该专用连接上通过一次性 Exec 完成，不额外建立连接。

### 对外模型

在 `ShellHandle` 附近增加通用 Handle：

```swift
struct SSHExecStreamHandle: Sendable {
    let id: UUID
    let stdout: AsyncStream<Data>
    let stderr: AsyncStream<Data>
}
```

为 `SSHClient` 增加：

```swift
func startExecStream(command: String) async throws -> SSHExecStreamHandle
func writeExecStream(_ data: Data, to id: UUID) async throws
func finishExecStreamInput(_ id: UUID) async
func closeExecStream(_ id: UUID) async
```

实现时名称可以调整，但必须具备启动、写入、半关闭 stdin、完全关闭四种生命周期能力。

### Channel 建立

底层 `SSHSession` 必须：

1. 打开 libssh2 `session` channel。
2. 通过 `libssh2_channel_process_startup(..., "exec", ...)` 启动命令。
3. 不调用 `libssh2_channel_request_pty_ex`。
4. 将 Channel 注册进现有非阻塞 I/O Loop。
5. 从 stream id `0` 读取 stdout。
6. 从 stream id `1` 读取 stderr。

### 写入行为

写入必须保持字节顺序，并在 libssh2 返回 `LIBSSH2_ERROR_EAGAIN` 时保证数据不丢失。

每个 Exec Stream 需要有序的 Pending Write Queue。I/O Loop 在 SSH Socket 可写时继续推进队列。不能让某个调用在 Actor 内持续自旋等待，否则会阻塞同一连接上的其他操作（例如版本预检 Exec）。

必须定义有界 Buffer 策略。队列超过限制时应施加背压或明确失败，不能无限增长内存。

### 读取行为

stdout 是协议数据，stderr 是诊断数据，两者不得共用 Continuation 或 Decoder。

读方向必须有界，禁止无界 `AsyncStream` 缓冲。当某个 Stream 的未消费缓冲达到上限时，I/O Loop 必须暂停对该 Channel 调用 `libssh2_channel_read_ex`，让 SSH Channel Window 关闭，把背压传导回远端；消费者跟上后恢复读取。背压机制使用 SSH 协议自带的 Window 流控，不另行发明缓冲丢弃或超限报错策略。

由于每个 Attachment 独占连接，不存在跨用途饿死问题。I/O Loop 仍应对同一连接内的少量 Channel（协议 Stream 与一次性 Exec）执行有限工作量，避免单次循环长时间占用 Actor。

### 结束和错误语义

实现必须区分：

- 远程正常 EOF
- 远程非零退出
- stdin 半关闭后继续读取剩余输出
- 用户主动 detach
- Task cancellation
- SSH 连接丢失
- Session 被立即 abort

stdout 和 stderr Stream 必须各自且仅结束一次。所有 Pending Writer 都必须以成功或错误恢复。关闭单个 Exec Stream 不得关闭所属 SSH Session，除非底层连接已经失效。

## 远程 Bridge 契约

固定 Herdr v0.7.4 后确认，当前完整 Workspace 入口是内部命令：

```sh
herdr --session vvterm remote-client-bridge
```

准确 revision、protocol 16、framing、frame 上限、公开 NDJSON 单终端接口和授权门槛见 `docs/specs/herdr-native-client-contract-v0.7.4.md`。期望的公开 `bridge client --stdio` 在该版本不存在，因此命令必须封装在唯一的 Command Builder 中。

Bridge 必须：

- 连接本机 Herdr Server/Runtime
- 在 stdin/stdout 与本地 Server Transport 之间复制 Herdr 协议帧
- stdout 只输出协议字节
- 日志和诊断只输出到 stderr
- stdin 关闭或本地 Server 结束客户端连接时退出
- 不申请 PTY

如果当前 Herdr 只有内部 Bridge 命令，Spike 可以暂时使用，但必须封装在唯一的 Command Builder 中。产品 UI 和 Application 层不能散落内部命令字符串。

## 版本预检

打开 Render Bridge 前，VVTerm 应通过现有一次性 Exec 能力执行结构化预检，获取：

- 远程 Herdr Binary Version
- 远程 Protocol Version
- Runtime/Server 是否可用
- 是否支持目标 Bridge

内置 Framework 同时暴露自身 Version 和 Protocol Version。第一版只接受严格匹配。

```swift
enum HerdrPreflightResult: Equatable {
    case compatible
    case binaryMissing
    case runtimeUnavailable
    case bridgeUnavailable
    case versionMismatch(client: String, remote: String)
    case protocolMismatch(client: Int, remote: Int)
}
```

实际命令和 JSON Schema 必须根据固定的 Herdr revision 验证。只要存在结构化结果，就不能解析面向人的文本输出。

`startWorkspaceConnection` 必须在创建 ClientKit 或打开 private bridge 前执行预检，并且只允许 `.compatible` 继续。`.runtimeUnavailable`、版本/协议不匹配和无效状态必须直接返回确定性错误，不能退化为等待 bridge 的 socket timeout。

Session Name 还受远端 Unix socket 完整路径长度限制。测试 fixture 和自动生成的临时 session 必须使用短名称；不能直接把完整 UUID 拼接到长前缀后作为 session name，否则 macOS 可能在输出结构化 status 前返回 `sockaddr_un.sun_path` 超限错误。

## VVTerm Feature 归属

新增独立 Feature：

```text
VVTerm/Features/Herdr/
├─ Domain/
│  ├─ HerdrRuntimeReference.swift
│  ├─ HerdrAttachment.swift
│  ├─ HerdrConnectionState.swift
│  └─ HerdrClientEvent.swift
├─ Application/
│  ├─ HerdrSessionController.swift
│  └─ HerdrPreflightService.swift
├─ Infrastructure/
│  ├─ HerdrClientKitAdapter.swift
│  ├─ HerdrSSHTransport.swift
│  └─ HerdrRemoteCommandBuilder.swift
└─ UI/
   ├─ HerdrWorkspaceView.swift
   ├─ HerdrWorkspaceView+iOS.swift
   └─ HerdrWorkspaceView+macOS.swift
```

可以复用当前 Feature/Core 边界中的 Ghostty 展示组件，但 Herdr Attachment 状态和关闭语义必须独立于 `TerminalTabManager`、tmux manager 和普通终端 Session。

### Domain Model

```swift
struct HerdrRuntimeReference: Hashable, Sendable {
    let serverId: UUID
    let sessionName: String
}

enum HerdrAttachmentMode: Hashable, Sendable {
    case workspace
    case observe(terminalId: String)
    case control(terminalId: String, takeover: Bool)
}

struct HerdrAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let runtime: HerdrRuntimeReference
    let mode: HerdrAttachmentMode
}
```

第一阶段产品可以只提供 `.workspace`，但模型中不能把 VVTerm Attachment、Herdr Runtime 和 Herdr Terminal 混为同一概念。

### 连接状态

```swift
enum HerdrConnectionState: Equatable, Sendable {
    case idle
    case preflighting
    case connecting
    case handshaking
    case attached
    case reconnecting
    case failed(HerdrConnectionFailure)
}
```

UI 必须分别展示并处理 Binary 缺失、版本不兼容、Bridge 失败、SSH 中断、协议错误和远程 Runtime 关闭。

## 数据流

### 连接与渲染

```text
用户打开 Herdr View
→ 执行版本预检
→ 创建 HerdrClientKit Client
→ 启动无 PTY SSH Exec Stream
→ 将 Client 初始 Hello 写入 SSH stdin
→ 将 SSH stdout 分块输入 HerdrClientKit
→ 每次状态变化后继续排空 Outbound Bytes
→ 将 ANSI Frame Event 送入 Ghostty
→ 协议握手成功后标记 Attachment 已连接
```

SSH Chunk 边界不等于 Herdr Frame 边界。增量 framing 必须由 `herdr-client-core` 负责。

### 输入

第一阶段将终端输入作为原始字节传递：

```text
Ghostty / Input Coordinator
→ HerdrSessionController
→ HerdrClientKit send_input
→ 取出 Outbound Protocol Bytes
→ HerdrSSHTransport write
```

粘贴内容在进入 Herdr 前必须遵守 VVTerm 现有 Paste Safety 和 Rich Paste Policy。

### Resize

只有当前拥有控制权的 Attachment 可以发出权威 Resize。交互式布局变化时应合并 Resize，避免大量消息淹没远程 Server。

### 顺序

同一 Attachment 的 Client Core 操作必须串行化。ANSI Frame、Title、Error 和状态变化必须按协议顺序处理。

## 生命周期与重连

iOS 后台运行不能被视为长期传输保证。

```text
App 离开前台
→ Attachment 可能关闭或丢失 SSH
→ 远程 Herdr Runtime 和 Agent 继续运行

App 返回前台
→ 创建新的 Transport Generation
→ 必要时重新预检
→ 重新连接并握手
→ 请求或接收 Full Redraw
→ 新 Attachment 获得有效控制权后才恢复输入
```

每次连接必须有单调变化的 Generation/Token。新的连接生效后，旧 Generation 的 Event、Frame、Error 和 Completion 全部丢弃。

Attachment 连接必须启用 SSH Keepalive 或应用层心跳，并定义明确的死连接判定阈值。Wi-Fi 与蜂窝切换产生的 Half-open TCP 必须在有限时间内被判定为连接丢失并进入重连流程，不得无限等待远端字节。

重连策略必须：

- App 在前台时使用有上限的指数退避
- 用户主动 detach 后停止重试
- 版本或协议不匹配时停止并提示操作
- 避免无意创建两个可写 Controller
- 取消旧 Stream Reader 和 Pending Write
- 收到 Full Redraw 前不得把旧画面视为当前状态

第一版不承诺后台连接不断开，只承诺远程计算持续运行和前台可确定恢复。

## 输入与交互范围

### 第一阶段

- 软件键盘文本和控制字节
- 硬件键盘输入
- VVTerm Terminal Accessory Key
- Paste
- 协议支持时发送 Focus Gained/Lost
- Terminal Resize

### 后续阶段

- 结构化 Herdr Key Event
- Mouse 和 iPad Pointer Event
- Touch-to-Pane 定位
- 原生 Herdr 导航控件
- Graphics 和 Clipboard Event
- Observe/Control/Takeover UI

键盘和终端输入修改必须遵循 VVTerm 回归策略：策略和路由逻辑使用 Unit Test，用户可见的键盘和 Focus 行为使用 iOS UI Test。

## 产品入口

技术 Spike 应先使用内部诊断入口，不要立即修改持久化 Tab Model。

Spike 成功后再加入正式连接 Tab：

```swift
static let herdr = ConnectionViewTab(
    id: "herdr",
    localizedKey: "Herdr",
    icon: "square.stack.3d.up"
)
```

产品化必须同步修改：

- `ConnectionViewTab`
- Tab 配置持久化
- iOS Content Routing
- macOS Content Routing
- Tab Strip 和 Toolbar
- 连接/断开生命周期
- Accessibility 和 Localization
- 适用的 Pro 限制

未知 Tab id 不得静默回退到普通 Terminal View。

## 结构化 Agent API

原生 Agent 列表和控制属于后续阶段，应使用单独的结构化 Bridge，例如：

```sh
herdr bridge api --stdio --session vvterm
```

建议分离：

```text
Render Bridge
  Herdr 二进制客户端协议
  完整 Workspace ANSI、Input、Resize、Redraw

API Bridge
  版本化 JSON 或 NDJSON
  Agent、Workspace、Pane、Command 和 Event
```

Render Protocol 不应演变为通用 UI 数据 API；面向人的 CLI 输出也不应成为长期应用协议。

后续可增加：

- Agent list/get/focus
- Observe Terminal
- 请求 Control 或显式 Takeover
- Workspace/Tab/Pane list 和 focus
- Lifecycle 和 Agent Status Event 订阅

## 安全要求

- 复用 VVTerm 现有 SSH Host Verification 和 Credential；HerdrClientKit 不接触认证信息。
- 日志不得包含 Credential、Private Key 或完整终端内容。
- 远程 stderr 和协议错误均按不可信文本处理。
- 在分配内存前验证 Frame Length 并设置上限。
- 拒绝畸形或过大的 C ABI DTO。
- Attachment 关闭时清空 Pending Input Buffer。
- 后续 Takeover 操作必须要求用户显式确认。
- 本阶段不得自动下载和执行替换版远程 Herdr binary。

## 许可证与分发

按当前项目决策，本规格不把 AGPL 合规方式或商业许可证作为设计、实现、测试或发布阻塞项。仓库仍记录确切 Herdr Source Revision、Client/Protocol Crate 的本地修改和 Framework 构建步骤，以保证技术可重现性。

## 测试策略

### SSH Transport Unit Test

如果无法在确定性 Unit Test 中直接运行 libssh2，应将 Channel Scheduling 和 Buffer Policy 与 C API 调用分离，通过 Fake Channel Driver 测试：

- 有序 Partial Write
- 重复 `EAGAIN`
- Pending Write 有界行为
- stdout/stderr 独立传递
- 正常 EOF
- 非零退出和 stderr
- 主动关闭
- Cancellation
- 连接丢失
- Continuation 只结束一次
- 读侧有界缓冲：达到上限时暂停读取，消费后恢复
- 同一连接内多 Channel 公平性

### Binary Echo Integration Test

接入 Herdr 前，先使用确定性的 Bridge Fixture 回显 Length-delimited Binary，并向 stderr 写入固定诊断内容。

覆盖：

- 协议允许时的零长度 Payload
- 1 Byte
- 包含 NUL、CR、LF 和终端控制字符的数据
- 32 KiB 边界值
- 至少 1 MiB 数据
- 快速连续发送大量小消息

### Herdr Client Core Test

覆盖：

- Fragmented 和 Coalesced Frame
- Hello/Welcome 成功
- Protocol Mismatch
- 畸形和超大 Frame
- ANSI Event 顺序
- Input Encoding
- Resize Encoding 和合并契约
- Server Shutdown
- Reconnect 和 Full Redraw
- C ABI Allocation/Release

另提供默认跳过的 real bridge smoke test。它可直接启动本机 Herdr，也可复用已认证的隔离 SSH fixture；测试必须使用唯一命名 session，并在结束时停止临时 server。Herdr 0.7.3 已完成 protocol 16 Welcome、首帧 `seq=1/full=true`、Resize、Input 和 Detach 的真实链路验证；v0.7.4 源码审计确认仍使用 protocol 16 和 `remote-client-bridge`，升级后的真实 smoke 仍需执行。该测试验证真实 wire contract，不替代 VVTerm libssh2 transport 与真机 UI 验证。

### VVTerm Application Test

覆盖：

- Preflight 各类结果
- Attachment 状态变化
- Generation 失效
- 丢弃旧 Frame 和旧 Error
- 前台重连
- 主动 Detach 停止重试
- Raw Input Routing
- Resize Ownership
- Remote Shutdown 展示

### UI Test

iOS 至少覆盖：

- 打开 Herdr Workspace
- 显示 Connecting/Failed/Attached 状态
- 键盘输入到达当前 Attachment
- 离开再返回时不产生重复 Reader
- 模拟断线后的重连展示

### 构建验证

每个非文档实现阶段都必须运行最窄且相关的测试，并验证：

- iOS Simulator Build/Test
- macOS Build/Test

Spike 完成前必须在真实 iPhone 上验证，但真机验证不能替代自动化测试。

## 交付阶段

### Phase 0：固定基线和契约

- 固定 VVTerm 和 Herdr Source Revision
- 确认实际 Herdr Bridge 和 Status Command
- 在 macOS 上通过管道手工验证 Bridge stdout 纯净性（例如 `herdr bridge client --stdio | xxd`），确认 stdout 只输出协议字节、诊断只进 stderr，并观察基本握手字节
- 记录准确 Protocol Version
- 定义 C ABI 所有权规则
- 加入技术 Spike 入口

退出标准：两个仓库和远程 Binary 都能从记录的 Revision 重现，且 Bridge stdout 纯净性和基本握手字节已在桌面环境人工验证。此项验证不写任何 Swift 代码即可完成，是后续所有阶段成立的前提。

### Phase 1：通用 SSH Exec Stream

- 增加通用 Handle 和 Lifecycle API
- 实现无 PTY Channel
- 将 stdout/stderr 和 Pending Write 接入 I/O Loop
- 增加 Fake Driver Unit Test
- 完成 Binary Echo Integration Test

退出标准：在 Fragmentation、Backpressure、并发 Terminal、Cancellation 和 EOF 情况下仍能无损传输二进制数据。

### Phase 2：最小 HerdrClientKit

- 提取 Protocol 和 Client Core Crate
- 定义 C ABI
- 构建 Apple XCFramework
- 增加 Swift Adapter Test

退出标准：Swift 可以在所有 Apple arm64 目标上创建 Client、完成 Fixture Handshake、接收 ANSI、编码 Input/Resize 并安全销毁 Client。

### Phase 3：真实端到端 Spike

- 通过 SSH 启动真实远程 Bridge
- 完成 Hello/Welcome
- 将真实 ANSI 输入 Ghostty
- 发送 Input 和 Resize
- 断开并重连到 Full Redraw

退出标准：真机 iOS 上的完整链路正常工作，且不使用 PTY 或本地子进程。

### Phase 4：生命周期加固

- 增加 Generation 失效机制
- 处理前后台切换
- 实现有界 Retry/Backoff
- 增加 Controller Ownership 保护
- 完成 Lifecycle 和 UI Regression Test

退出标准：反复网络和生命周期切换不会泄漏 Channel，也不会传递旧连接的输入输出。

### Phase 5：产品集成

- 增加 Herdr Connection Tab 和设置
- 增加平台专属 UI Shell
- 加入 Localization、Accessibility 和错误恢复
- 验证 iOS/macOS Parity

退出标准：用户可以通过正式产品入口打开、使用、Detach 和恢复 Herdr Workspace。

### Phase 6：原生 Agent 体验

- 定义并实现结构化 API Bridge
- 增加 Agent List 和 Status
- 增加 Observe/Control/Takeover
- 按需要增加 Workspace/Tab/Pane 导航

退出标准：原生 UI 使用结构化数据，并与 Terminal Render Frame 保持解耦。

## 原子提交计划

建议按以下顺序提交：

1. 增加本架构规格。
2. 增加通用 Exec Stream Domain Type 和可测试的 Buffer/State Logic。
3. 增加 libssh2 无 PTY Exec Stream。
4. 增加 Binary Echo Integration Test。
5. 在 Herdr 仓库提取 Protocol/Client Core。
6. 增加 Apple C ABI 和可重现 XCFramework 构建。
7. 在 VVTerm 增加 `HerdrClientKitAdapter` 和 Fixture Test。
8. 增加 `HerdrSSHTransport` 和诊断用端到端 Spike。
9. 增加 Ghostty Render、Input 和 Resize。
10. 增加 Reconnect/Lifecycle 加固和测试。
11. 增加正式 Connection Tab。
12. 将结构化 Agent API 作为独立后续变更。

不得把 Herdr 源码拆分、SSH Transport、产品 UI 和 Agent 功能混在一个 Commit 或 PR 中。

## Spike 成功标准

只有全部满足以下条件，才能认为原生客户端方向成立：

1. iPhone Build 能加载 `HerdrClientKit.xcframework`。
2. VVTerm 能打开不申请 PTY 的长期 SSH Exec Stream。
3. 嵌入式客户端能与固定版本远程 Herdr 完成握手。
4. Ghostty 能显示服务器产生的真实 ANSI Frame。
5. 键盘输入能到达远程 Herdr Runtime。
6. Resize 能改变远程布局。
7. stderr 输出诊断时不会污染 stdout 协议帧。
8. 断线能关闭旧 Stream 和所有 Pending Writer。
9. 客户端断开后远程 Agent/Runtime 继续运行。
10. 重连建立新 Generation 并收到 Full Redraw。
11. Protocol Mismatch 能产生确定性的用户错误。
12. Herdr Attachment 使用前后，普通 SSH Terminal 仍然正常。

## 暂停或重新评估条件

Spike 遇到以下任一情况，应暂停产品化并重新评估：

- Herdr Client 无法在不维护大范围长期 Fork 的情况下与 CLI、Terminal、Process 或 Server 分离。
- 所选 Herdr Server 不存在 stdout 只输出协议数据的 Bridge。
- Protocol Frame 无法设置上限或安全增量解析。
- libssh2 无法在专用连接上同时保证无损有界写入和可暂停恢复的读取。
- Reconnect 无法确定性获得 Full Redraw 或安全 Controller 状态。

原生 Spike 失败并不否定更简单的 Herdr TUI-over-SSH-PTY 方案；后者仍可作为低耦合降级路线。

## 待确认问题

- 第一个 Spike 使用的 Herdr 源码路径和固定 Revision 是什么？
- 该 Revision 的 stdio bridge 命令和 Wire Handshake 是什么？
- 重连和 Takeover 后，Server 是否仍保证发送 Full Redraw？首次新 session handshake 已在 Herdr 0.7.3 真实远端验证，v0.7.4 仍需复验。
- Reconnect 和 Takeover 时如何表达 Terminal Controller Ownership？
- 嵌入式客户端允许的最大 Inbound Frame Size 是多少？
- 第一版正式入口应是独立 Connection Tab，还是 Server-level Remote Experience Mode？

`HerdrClientKit.xcframework` 已确定按需本地构建：提交 Rust/C ABI 源码与构建脚本，忽略生成的 `Vendor/HerdrClientKit/build/HerdrClientKit.xcframework`。

这些问题必须在对应实现阶段开始前解决，但不阻塞 Phase 1 的通用 SSH Exec Stream。
