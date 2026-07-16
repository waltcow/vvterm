# Herdr 原生客户端实施计划

日期：2026-07-12

权威规格：`docs/specs/herdr-native-client.md`

## 当前进度

- Batch 1 已完成：有界异步字节流、写队列及确定性测试已落地。
- Batch 2 已完成首版：无 PTY Exec Stream 已接入 libssh2 I/O loop，并覆盖写入、半关闭、关闭和错误生命周期。
- Batch 3 已完成 fixture 和 opt-in 集成测试代码；仍需在配置了真实 SSH fixture 的环境执行，才能满足该 Batch 的退出标准。
- Phase 0 契约审计已刷新到当前 stable：固定 Herdr `v0.7.4` / revision `50aaa2ec046ee26ff407c20f49de496f522512a8` / protocol 16，并确认完整 Workspace 私有 bridge 与公开单终端 NDJSON 的边界未变。
- Batch 4 已完成首版：Rust protocol/core、panic-safe C ABI、三个 Apple arm64 slice、按需构建的 XCFramework、Swift Adapter、golden fixture tests 和 opt-in real bridge smoke test 已落地。
- 2026-07-12 已在隔离的 macOS SSH fixture 上对 Herdr 0.7.3 运行 real bridge smoke：完成 protocol 16 Welcome、首帧 `seq=1/full=true` ANSI redraw、resize、input 和 detach，临时命名 session 已停止。该结果确认 ClientKit 与真实远端 wire contract 兼容，但不替代 VVTerm libssh2 pump 和真机验证。
- 2026-07-12 已在预启动的 disposable session 上通过真实 XCTest：`VVTerm SSHClient/libssh2 -> HerdrWorkspaceConnection -> HerdrClientKit` 完成 Welcome、首帧 Full Redraw、resize、input 和 detach，1 test passed。测试随后停止临时 server。
- Batch 5 的协议和首个真机预览链路已完成首版：结构化 SSH Exec 结果、preflight service、唯一 Command Builder、NDJSON terminal session codec、可注入的 `HerdrSSHTransport` 和 `HerdrWorkspaceConnection` pump 已落地；真实 ANSI event 已接入 Ghostty，raw input 与 resize 已回送 Herdr ClientKit。
- 已确认一个独立启动边界：Herdr 0.7.3 在 server 未运行时，通过 VVTerm 无 PTY libssh2 直接调用 `remote-client-bridge`，隐式 headless server 的 startup pane 会在 client socket ready 前收到 `SIGHUP`。协议链路本身正常，但正式入口必须先解决 server bootstrap/persistence 契约，不能把 Herdr 0.7.3 隐式 auto-start 当作可靠前提。
- `startWorkspaceConnection` 已强制执行结构化 preflight，只有 `.compatible` 才打开 bridge。真实 stopped-session XCTest 返回 `.runtimeUnavailable`；预启动 session 的完整链路随后再次通过。
- 临时 session 名必须保持简短。完整 UUID 加长前缀会令 Herdr socket 路径超过 macOS `sockaddr_un.sun_path`，导致 status 在输出 JSON 前失败；fixture 已改用 8 位随机后缀。
- 2026-07-12 已增加独立 `Herdr` Connection View Tab、设置持久化、iOS/macOS 平台 Terminal Surface、Connecting/Failed/Attached 状态与 Retry。arm64 iOS Simulator、macOS arm64 和签名 iPhone device build 均通过，预览包已安装并完成设备侧人工确认。
- Herdr terminal resize 已增加 120ms leading/trailing coalescing：首个有效尺寸立即发送，连续变化只保留最新尺寸，重复、无效和回到已发送尺寸的事件被丢弃；5 个确定性 XCTest 已通过。
- 真机预览不使用显式 `herdr server` headless 启动。远端通过标准 `herdr --session <session>` TUI 启动真实 runtime，iPhone Herdr Tab 作为独立原生 bridge client 连接该 fixture。
- Herdr Attachment 已完成连接代际隔离，旧连接的 frame、error、completion 和延迟重连任务不能污染或清空新连接。
- Herdr Tab 首次挂载后会保留同一 coordinator、Ghostty terminal、远端 session identity 和输入状态；切到其他 Tab 只暂停渲染，不销毁连接或画面。
- 用户 Retry、网络恢复和前台恢复都会复用当前 Herdr session；Wi-Fi/蜂窝变化及 SSH 中断进入明确的 suspended/reconnecting/failed 状态，并使用 500/1000/2000/5000 ms 有界退避。
- iOS 后台会挂起连接和渲染，`inactive` 不会提前恢复，重新进入前台后才恢复同一 session；对应状态策略单测和 iOS UI 回归测试已通过。

## 实施原则

- Herdr 协议、SSH 传输、Ghostty 渲染和产品 UI 分批交付，不放进同一提交。
- `Core/SSH` 只提供通用字节流，不理解 Herdr 消息。
- 每个 Herdr Attachment 使用独立 `SSHClient` 和独立 TCP/SSH 连接。
- 第一条真实链路必须是无 PTY 的长期 Exec Stream；PTY TUI 只作为独立降级路线。
- 每批代码先补最窄的确定性测试，再接生产路径。
- 每个非文档批次验证 macOS 和 iOS Simulator；端到端 Spike 还必须验证真实 iPhone。

## 当前阻塞与非阻塞边界

Phase 1 不依赖 Herdr 仓库。Phase 2 的协议基线已经确定：

- 固定 source tag 为 `v0.7.4`，revision 为 `50aaa2ec046ee26ff407c20f49de496f522512a8`。
- 完整 Workspace 使用内部 `remote-client-bridge` 透明代理 private client protocol 16。
- 协议 framing 为 u32 little-endian length + bincode 2 standard config；普通 2 MiB，graphics 32 MiB。
- 公开 `terminal session observe/control` 是单 terminal NDJSON，不替代完整 Workspace ClientKit。
- Controller Ownership：单 terminal 只有一个 writable controller，`--takeover` 替换 owner；observer 无写权限。

仍待确定：

- 重连、takeover 和不同 session 状态下是否都确定性保证 Full Redraw 与安全 Controller Ownership。

已确定 XCFramework 采用按需本地构建：源码、C Header 和构建脚本提交到仓库，`build/HerdrClientKit.xcframework` 不提交。C ABI ownership 和错误释放规则记录在 Header 与 `Vendor/HerdrClientKit/README.md`。

## Batch 1：通用 Exec Stream 基础

目标：建立与 Herdr 无关的、可测试的二进制流和写队列。

- 增加 `SSHExecStreamHandle`，分别暴露 stdout 和 stderr。
- 增加单消费者、有界、不丢数据的异步字节流。
- 增加有界、有序的 pending write queue。
- 覆盖 partial write、顺序、buffer limit、消费后恢复和 terminal error。

退出标准：基础类型在 macOS/iOS 编译通过，确定性单测通过。

## Batch 2：libssh2 无 PTY Exec Stream

目标：把 Batch 1 接入现有 `SSHSession` 非阻塞 I/O loop。

- `startExecStream(command:)` 打开 session channel 并执行 exec，不申请 PTY。
- `writeExecStream` 将写入排队，由 I/O loop 推进 partial write 和 `EAGAIN`。
- stdout/stderr 分开读取；缓冲满时暂停对应 stream 的 `read_ex`。
- 支持 stdin 半关闭、主动关闭、取消、远程 EOF、非零退出和连接丢失。
- 单次 loop 对每个 channel 只推进有限工作量。

退出标准：API 编译通过；writer/reader completion 恰好结束一次；普通 Shell 与一次性 Exec 路径不回归。

## Batch 3：Binary Echo Integration Fixture

目标：在接入 Herdr 前证明二进制透明传输。

- 增加远端或本机 SSH fixture，stdout 回显 length-delimited binary，stderr 输出固定诊断。
- 覆盖 NUL、CR/LF、控制字符、32 KiB、1 MiB 和大量小消息。
- 并发打开普通 Terminal，验证 Exec Stream 不污染 PTY 数据。
- 验证取消、EOF、半关闭和背压。

退出标准：固定 fixture 上逐字节一致，stdout/stderr 无串流。

## Batch 4：HerdrClientKit

目标：在 Herdr 仓库提取与传输无关的最小客户端核心。

- 固定 Herdr revision 和协议版本。
- 提取 protocol framing、incremental decoder、handshake、outbound/event queue。
- 定义窄 C ABI、panic boundary、buffer ownership 和错误释放规则。
- 构建 iOS device、iOS Simulator、macOS arm64 static libraries 和 XCFramework。
- 在 VVTerm 增加 `HerdrClientKitAdapter` fixture tests。

退出标准：Swift 在三个 Apple arm64 slice 上可完成 fixture handshake、ANSI、input、resize 和销毁。

## Batch 5：真实端到端诊断 Spike

目标：验证原生方向最关键的完整链路，暂不修改持久化 Tab Model。

- 在 `Features/Herdr` 增加 Domain、Application 和 Infrastructure 边界。
- 结构化 preflight 严格比较 binary/protocol version。
- 通过专用 SSHClient 启动真实 stdio bridge。
- 将 stdout 协议帧输入 HerdrClientKit，将 ANSI event 输入 Ghostty。
- 路由 raw input、paste safety 和合并后的 resize。
- 断开并重连，验证新 generation 和 Full Redraw。

退出标准：真实 iPhone 完成握手、渲染、输入、resize、断开和恢复；远程 runtime 不终止。

## Batch 6：生命周期加固

目标：把诊断链路提升到可重复使用的 Attachment controller。

- Generation token 丢弃旧 frame/error/completion。
- 前台有限指数退避；detach 和协议不匹配停止重试。
- 前后台、Wi-Fi/蜂窝切换和 half-open timeout。
- Controller Ownership 防止双写。
- Unit Test + iOS UI Test 覆盖连接状态和重复 reader 回归。

退出标准：生命周期压力测试无 channel 泄漏、旧帧或重复输入。

当前状态：已实现 generation 失效、重复连接抑制、重连任务代际隔离、前后台恢复、网络变化、SSH 中断分类、有界退避、Retry 保持 session、Tab/画面/输入状态保活，以及状态策略和 iOS UI regression tests。仍待完成主动 half-open timeout/heartbeat 和协议层 Controller Ownership/Takeover 保护。

## Batch 7：产品入口

目标：增加正式 Herdr Connection Tab 和平台 UI shell。

- 更新 `ConnectionViewTab`、配置持久化和未知 id 错误处理。
- 分别实现 `HerdrWorkspaceView+iOS.swift` 与 `HerdrWorkspaceView+macOS.swift`。
- 接入 localization、accessibility、错误恢复和适用的 Pro 限制。
- 保持 `TerminalTabManager`、tmux 生命周期与 Herdr Attachment 分离。

退出标准：iOS/macOS 均可从正式入口打开、使用、detach 和恢复 Herdr Workspace。

当前状态：独立 Tab、首个预览 shell、Retry/reconnect 产品动作和生命周期 UI test 已接入；localization 完整覆盖、Pro 限制和显式 detach 产品动作仍待完成。

## 建议原子提交

1. `docs: add Herdr native client implementation plan`
2. `test: cover bounded SSH exec stream buffers`
3. `feat: add generic SSH exec stream transport`
4. `test: add binary exec stream integration fixture`
5. `feat: add HerdrClientKit adapter and fixture tests`
6. `feat: add diagnostic Herdr end-to-end attachment`
7. `feat: harden Herdr attachment lifecycle`
8. `feat: add Herdr connection tab`

结构化 Agent API、Observe/Control/Takeover 单独进入后续计划，不进入上述 Spike PR。
