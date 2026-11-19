# Tailcat 缓冲/所有权修复交接（native allocator / lifetime）

本文件把临时任务报告 `/tmp/eir-native-finish/result.md` 固化为仓库交接文档，供后续业务汇总与打包代理使用。范围：原生桥接、Dart FFI、专项测试；不含 UI、应用编译、安装、打包或发布。

## 必须向打包代理传达的关键事实（不可遗漏）

- 已签入仓的产品原生库（如 `native/tailcat/libtailcat.so`、仓库根目录 `libtailcat.so`，以及各平台 DLL/dylib）**都不含**新增导出符号 `TailcatFree`。旧二进制不可作为新 FFI 契约已生效的证据。
- 新源码要求所有由 Go 库分配的缓冲区（state 回调 `info`、data 回调 `data`、`TailcatStartServer` 返回的地址字符串 `r0`）**只能**通过同库的 `TailcatFree` 释放；Dart 分配的缓冲区（`toNativeUtf8` 的服务端地址、`sendBinary` 的 payload）仍用 `calloc.free`。
- 加载旧库时 Dart 会以 `UnsupportedError('Tailcat native library is missing TailcatFree; rebuild native/tailcat (...)')` 干净失败，没有不安全的回退分配器。这是预期的告警信号，**不是**绿灯结果。
- 打包前必须为所有发布平台（Windows DLL、Linux `.so`、macOS `.dylib`、以及适用的 Android/iOS 目标）从更新后的 `native/tailcat/tailcat_bridge.go` 重新构建原生库，确保 `TailcatFree` 存在；头文件声明需与 `native/tailcat/libtailcat.h` 一致。最终交付二进制必须匹配新 ABI。

状态：原生 + Dart 桥接修复及专项测试完成。未做 UI、应用编译、安装、打包或发布；未覆盖任何已签入/生成的产品二进制。仅修改任务所有权内的文件，其他代理改动均未触碰（`git status --short` 已核对）。

## 变更 API / ABI

Go `c-shared` ABI 新增导出符号：

```c
extern void TailcatFree(void* ptr);
```

`TailcatFree` 对同库用 `C.CString` / `C.CBytes` 分配的缓冲区调用 `C.free`。这是 Dart 释放这类缓冲区的唯一合法途径。

所有权契约：原生回调返回后，Go 缓冲区归 Dart 侧所有，必须且只能通过 `TailcatFree` 释放一次，没有 `calloc.free` 回退。

## 修改文件（均在任务所有权内）

- `native/tailcat/tailcat_bridge.go` — 新增导出 `TailcatFree`（调用 `C.free`）。原有 send mutex/`writeFull`、连接关闭解锁、回调屏障、负 send 结果处理均未改动。
- `native/tailcat/libtailcat.h` — 新增 `TailcatFree` 声明，使签入的 ABI 头文件与 freshly generated cgo 头文件一致（对比见下）。
- `native/tailcat/tailcat_ctest.go`（build tag `tailcat_ctest`）— 测试捕获 helper 改用 `TailcatFree` 释放移交缓冲区；新增 `sharedLibraryExports()`，用 `dlopen`/`dlsym` 检查真实构建的共享库。
- `native/tailcat/tailcat_bridge_test.go`（build tag `tailcat_ctest`）— 新增 `TestTransferredBuffersAreReleasedByExportedAllocator`（32 次 `C.CString`/`C.CBytes` 分配/移交/释放循环）和 `TestSharedLibraryExportsFullABI`（env 门控 `dlsym` 校验六个导出符号）。
- `lib/core/transport/tailcat_ffi.dart` — 用一组进程生命周期的 listener 对替换每实例 `NativeCallable`；新增按 session id 的路由表、库解析的 `TailcatFree`、early allocator 解析与干净失败、异常安全的原生入口、close 时移除路由；`sendFrame` 错误传播保持不变。
- `test/core/tailcat_transport_test.dart` — 按路由/分配器模型重写：活路由投递、注入分配器验证 free-once、close 后排队的迟到回调释放但不投递、未知 session 释放、投递失败隔离、路由移除/幂等 close、send 结果传播。

## 生命周期 / 路由行为

- `_dataCallable` / `_stateCallable` 为静态、创建一次、永不关闭。原生 listener 把回调 post 到 isolate event loop；每实例 callable 可能在仍有排队调用时被关闭，现已不可能。
- `_routes: Map<int, TailcatTransport>` 以原生 session id 为键。静态回调与 `start*`/`close` 都在同一 isolate event loop 上运行，无需锁。`close()` 在调用原生 `TailcatClose` 前先移除路由；迟到的回调找不到路由，会通过 `TailcatFree` 释放其 C 缓冲区，且不接触已关闭的 transport（即使 Dart 对象已不存在）。
- 两个原生入口都用 `try/catch` 包裹投递，并在单独的受保护路径释放，确保没有 Dart 异常跨越原生边界，且每个缓冲区只释放一次。
- 启动竞态：`TailcatStartServer`/`TailcatStartClient` 在 FFI 调用期间 post 首个 state 回调，但 listener 回调在 event loop 上投递。FFI 调用返回后立即同步存储 session id 并注册路由，早于任何排队回调被投递；未知 id 回调被防御性地释放并忽略。
- `_ensureNativeAllocator()` 在任何原生 session 启动前解析 `TailcatFree`。陈旧库会抛出 `UnsupportedError('Tailcat native library is missing TailcatFree; rebuild native/tailcat (...)')`；无不安全分配器回退。

## 原任务专项测试结果（历史证据，供追溯）

所有命令从 `/workspace/projects/Eir` 执行（Go 从 `native/tailcat`）。本交接文档仅固化该次报告，不代表本轮新跑的全量回归；本轮全量结果见 [FINAL-BUSINESS-TEST-HANDOFF.md](FINAL-BUSINESS-TEST-HANDOFF.md)。

### Go

```
gofmt -w tailcat_bridge.go tailcat_ctest.go tailcat_bridge_test.go
go build -buildmode=c-shared -o /tmp/eir-tailcat-build/libtailcat.so .
```
`BUILD_OK`（临时库写在仓库外）。

```
go test -v -race -count=1 -tags tailcat_ctest ./...
```
PASS 9/9，`ok test 1.043s`：
`TestSharedLibraryExportsFullABI`（本次无 env 时跳过）、`TestNotifyStateTransfersStringOwnership`、`TestTransferredBuffersAreReleasedByExportedAllocator`、`TestInvokeDataCopiesGoBuffer`、`TestReadLoopAndCloseStopCallbacks`、`TestConcurrentSendsKeepWholeFrames`、`TestSendHandlesShortWrites`、`TestSendTreatsZeroLengthWriteAsFailure`、`TestSendReportsMissingNilAndFailedConnections`、`TestCloseUnblocksInFlightSend`。

```
TAILCAT_TEST_SHARED_LIB=/tmp/eir-tailcat-build/libtailcat.so \
  go test -v -count=1 -tags tailcat_ctest ./...
```
PASS 10/10，`ok test 0.032s` — 包含 `TestSharedLibraryExportsFullABI`，用 `dlopen`/`dlsym` 校验真实构建库中六个导出符号：`TailcatStartServer`、`TailcatStartClient`、`TailcatSend`、`TailcatIsDirect`、`TailcatClose`、`TailcatFree`。

```
go test -count=10 -tags tailcat_ctest ./...      -> ok test 0.233s
go test -tags tailcat_ctest ./...                -> ok test 0.027s
go vet ./...                                     -> exit 0
go vet -tags tailcat_ctest ./...                 -> exit 0
go test ./...                                    -> ? test [no test files]
```
（`tailcat_ctest` build tag 必需，因为 Go 不允许在 `_test.go` 中 `import "C"`；plain `go test` 保持干净。）

### 真实桥接共享库 C fixture（仅在仓库外构建）

fixture 源码/二进制：`/tmp/eir-tailcat-build/bridge_fixture.c` 和 `bridge_fixture`，链接新构建的 `/tmp/eir-tailcat-build/libtailcat.so`。它注册 C 回调，对每个 Go 分配的 payload 调用 `TailcatFree`，并用同样方式释放返回的服务端地址字符串。

```
gcc -std=c11 -Wall -Wextra -I. bridge_fixture.c -L. -ltailcat -o bridge_fixture \
    -Wl,-rpath,/tmp/eir-tailcat-build -pthread
timeout 30 ./bridge_fixture
```
输出：`addr=<tailcat addr> id=1`、`state-info=listening`、`state callbacks=1 frees=1`、`bridge fixture PASS`，exit 0。无 double free 或跨堆崩溃；C 侧调用者可通过导出符号释放 Go 缓冲区。

### Dart

```
flutter test test/core/tailcat_transport_test.dart --reporter expanded
```
PASS 9/9，`All tests passed!`：活文本路由投递 + free-once、活二进制路由投递 + free-once、state 路由 + free-once、close 后排队的迟到回调释放但不投递、未知 session 缓冲区仍释放、投递失败不越界且仍释放一次、close 移除路由且幂等、负 send 结果抛错、零 send 结果成功。

```
flutter analyze lib/core/transport/tailcat_ffi.dart test/core/tailcat_transport_test.dart
```
`No issues found!`（0.8s）。

### 旧二进制 / 缺失符号

```
nm -D native/tailcat/libtailcat.so | grep Tailcat
```
签入的旧 `libtailcat.so` 导出 `TailcatStartServer/StartClient/Send/IsDirect/Close` 但**不**导出 `TailcatFree`；新构建的临时库导出全部六个。`dart /tmp/eir-tailcat-build/probe.dart` 加载旧库得到：`clean lookup failure: ArgumentError: Invalid argument(s): Failed to lookup symbol 'TailcatFree': ... undefined symbol: TailcatFree` — `_ensureNativeAllocator` 将其转换为上述可操作的 `UnsupportedError`。没有回退触发。

### ABI 头文件一致性

```
diff -u native/tailcat/libtailcat.h /tmp/eir-tailcat-build/libtailcat.h
```
唯一剩余差异是 cgo 注释的装饰性差别（`/* package command-line-arguments */` vs `/* package test */`），取决于临时构建的调用方式，无 ABI 影响。所有 struct/typedef 声明和六个导出函数声明逐字节相同，包括 cgo 生成位置的 `extern void TailcatFree(void* ptr);`。

## 缺口 / 诚实限制

- 签入的 `native/tailcat/libtailcat.so` 是旧二进制，故意未替换。它缺少 `TailcatFree`；在库重建前 Dart 会以上述 `UnsupportedError` 干净失败。这是预期信号，不是陈旧二进制的绿灯结果。
- C fixture 只通过 `TailcatFree` 验证了 state 回调缓冲区和返回的地址字符串（均为 Go 分配）。未在真实 Tailcat 连接上跑完整 client/server 数据帧交换；data-callback 所有权由 Go tagged 测试覆盖（`TestInvokeDataCopiesGoBuffer`、`TestTransferredBuffersAreReleasedByExportedAllocator`），两类回调的 Go-to-C 契约一致。
- Dart 测试注入分配器（`freeOverride`）验证路由和 free-once 逻辑，不加载旧/原生库；真实 ABI 路径由 C fixture 和 env 门控 `dlsym` 测试覆盖。
- 本任务未构建或验证 Windows/macOS/Android/iOS 二进制。跨堆修复是结构性的（同库 `C.free`），但平台二进制必须在各自目标重建和运行。
- 未对无关编译做大范围重试。`transport_dual_engine_test.dart` 及其他代理文件未触碰；其中失败不在本任务范围内。

## 打包前的剩余要求

从更新后的 `native/tailcat/tailcat_bridge.go` 为所有发布平台重建原生库，确保新 `TailcatFree` 符号存在（Windows DLL、Linux `.so`、macOS `.dylib`，以及适用的 Android/iOS 目标），并交付与 `native/tailcat/libtailcat.h` 一致的头文件/声明。之后可运行既有应用打包/发布流程。不要将旧签入 `libtailcat.so` 当作新 FFI 契约已生效的证据。本任务未做应用编译、安装、打包或发布，也未覆盖任何签入/生成的产品二进制。
