# Android Tailcat 原生库 16KB 页对齐与构建配置交接报告

本文档记录针对 [FIXED-WEB-ARTIFACT-ACCEPTANCE.md 第七节第 3 项](file:///workspace/projects/Eir/docs/FIXED-WEB-ARTIFACT-ACCEPTANCE.md#L129-L133) 所报告的 `arm64-v8a` 原生库 ELF 16KB 页对齐风险的处理过程、真实检查结果与环境限制。

---

## 一、问题背景

在 `docs/FIXED-WEB-ARTIFACT-ACCEPTANCE.md` §7.3 中报告：
> `lib/arm64-v8a/libtailcat.so` 的 ELF `LOAD` 段 `p_align=0x1000`（4KB），而 `libapp.so`/`libflutter.so` 为 `0x10000`。APK 的 zip 对齐已通过 16KB 校验，但该原生库自身的 ELF 段对齐不是 16KB。若目标设备启用 16KB 页（Android 15+ 部分设备），存在 `dlopen` 失败风险。

在 Android 15 及后续系统中，当系统以 16KB 物理页大小运行时，动态链接器 (`linker64`) 会强制校验加载的 ELF 共享目标文件的每个 `LOAD` 段对齐值 `p_align >= 0x4000` (16384 字节)；若小于 16KB（例如旧版本的 `0x1000` / 4KB），`dlopen()` 将直接报错退出。

---

## 二、处理范围与执行原则

遵照当前阶段调度指令：
1. **专注范围**：仅处理 Tailcat 原生库及其构建配置，**不修改任何业务逻辑与 UI 界面代码**。
2. **构建边界**：**暂不构建整包 APK**、**暂不执行设备安装**、**暂不发布**。
3. **工具与脚本沉淀**：建立自动化构建与静态校验脚本 [tool/build_tailcat_android.sh](file:///workspace/projects/Eir/tool/build_tailcat_android.sh)，确保编译流程可追溯、可复现、可回归。

---

## 三、构建配置与工具链

### 1. 编译工具链与环境
- **Go 编译器**：`go version go1.24.4 linux/amd64`
- **NDK 版本**：Android NDK r28 (`/opt/android-sdk/ndk/28.2.13676358`)
- **C 交叉编译器**：
  - `arm64-v8a`: `$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang`
  - `x86_64`: `$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android24-clang`
- **目标 API Level**：`android-24`（与 `android/app/build.gradle.kts` 的 `minSdk = 24` 保持一致）

### 2. 16KB 对齐构建参数
在 Go 调用外部链接器（LLVM lld）时，显式指定 max-page-size 链接器参数：
```bash
-ldflags="-extldflags '-Wl,-z,max-page-size=16384'"
```
该参数确保 lld 在布局 ELF 各 `LOAD` 程序头时，虚拟地址与段偏移均按 16,384 字节（`0x4000`）边界对齐。

### 3. 构建与校验脚本
新增脚本 [tool/build_tailcat_android.sh](file:///workspace/projects/Eir/tool/build_tailcat_android.sh)，支持以下命令：
- `./tool/build_tailcat_android.sh all`：编译并静态验证 `arm64-v8a` 与 `x86_64` 两组架构；
- `./tool/build_tailcat_android.sh arm64`：仅编译并验证 `arm64-v8a`；
- `./tool/build_tailcat_android.sh x86_64`：仅编译并验证 `x86_64`；
- `./tool/build_tailcat_android.sh verify`：仅对现有库执行 16KB 段对齐及 FFI 导出符号门禁校验。

---

## 四、真实产物检查结果

### 1. 产物路径与指纹

| 架构 / ABI | 产物物理路径 | 文件大小 | SHA-256 哈希值 |
| :--- | :--- | :--- | :--- |
| **`arm64-v8a`** | [android/app/src/main/jniLibs/arm64-v8a/libtailcat.so](file:///workspace/projects/Eir/android/app/src/main/jniLibs/arm64-v8a/libtailcat.so) | 27,127,696 字节 | `eff9a36375a404e201fff2a0e573a33774b9044d7f13a5eb51fbd202893165ad` |
| **`x86_64`** | [android/app/src/main/jniLibs/x86_64/libtailcat.so](file:///workspace/projects/Eir/android/app/src/main/jniLibs/x86_64/libtailcat.so) | 28,979,592 字节 | `2df0a0b3f5079713acbece7f846110a8cff37103565503f99cd7d61760c6c747` |

### 2. ELF LOAD 段 16KB 页对齐实测 (`readelf -l`)

#### (1) `arm64-v8a/libtailcat.so` 实测输出：
```text
程序头：
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x0000000000000040 0x0000000000000040
                 0x0000000000000230 0x0000000000000230  R      0x8
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x00000000008f6918 0x00000000008f6918  R      0x4000
  LOAD           0x00000000008f6920 0x00000000008fa920 0x00000000008fa920
                 0x00000000006ad1e0 0x00000000006ad1e0  R E    0x4000
  LOAD           0x0000000000fa3b00 0x0000000000fabb00 0x0000000000fabb00
                 0x00000000002556d0 0x0000000000256500  RW     0x4000
  LOAD           0x00000000011f91d0 0x00000000012051d0 0x00000000012051d0
                 0x0000000000074b30 0x00000000020c8ae8  RW     0x4000
```
- **结论**：全部 4 个 `LOAD` 程序头段的 `Align` 均为 `0x4000`（16,384 字节 / 16KB），原 `0x1000`（4KB）风险已被彻底消除。

#### (2) `x86_64/libtailcat.so` 实测输出：
```text
程序头：
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x0000000000000040 0x0000000000000040
                 0x0000000000000230 0x0000000000000230  R      0x8
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x000000000092a98c 0x000000000092a98c  R      0x4000
  LOAD           0x000000000092a9c0 0x000000000092e9c0 0x000000000092e9c0
                 0x00000000007d4a00 0x00000000007d4a00  R E    0x4000
  LOAD           0x00000000010ff3c0 0x00000000011073c0 0x00000000011073c0
                 0x00000000002550c8 0x0000000000255c40  RW     0x4000
  LOAD           0x0000000001354490 0x0000000001360490 0x0000000001360490
                 0x0000000000074b90 0x00000000020c2238  RW     0x4000
```
- **结论**：全部 4 个 `LOAD` 程序头段的 `Align` 均为 `0x4000`（16KB）。

### 3. FFI 导出符号与 ABI 契约完整性 (`nm -D`)

两架构均完整导出全部 6 项核心 FFI 函数，特别是内存安全释放入口 `TailcatFree`：
- `TailcatStartServer`
- `TailcatStartClient`
- `TailcatSend`
- `TailcatIsDirect`
- `TailcatClose`
- `TailcatFree`

实测 `arm64-v8a` 符号输出：
```text
0000000000fa6770 T TailcatClose
0000000000fa6584 T TailcatFree
0000000000fa671c T TailcatIsDirect
0000000000fa66a0 T TailcatSend
0000000000fa6638 T TailcatStartClient
0000000000fa65d4 T TailcatStartServer
```

实测 `x86_64` 符号输出：
```text
00000000011020ac T TailcatClose
0000000001101ec0 T TailcatFree
0000000001102058 T TailcatIsDirect
0000000001101fdc T TailcatSend
0000000001101f74 T TailcatStartClient
0000000001101f10 T TailcatStartServer
```

---

## 五、单元测试与 Dart 回归验证

1. **Go 侧底层单元测试**：
   - 执行命令：`cd native/tailcat && go test -v -tags tailcat_ctest .`
   - 结果：**10 项单元测试全部通过**（覆盖字符串/切片所有权转移、导出分配器释放、跨 Go/C 回调并发安全等）。
2. **Dart 侧 Tailcat FFI Transport 回归**：
   - 执行命令：`flutter test test/core/tailcat_transport_test.dart`
   - 结果：**9 项单元测试全部通过**（覆盖实时路由释放、幂等关闭、生命周期内存安全等）。

---

## 六、真实限制与验收声明 (Non-Exemptions)

> [!IMPORTANT]
> **静态原生库编译与对齐验证通过，不等于整包 APK 构建完成或 Android 15+ 真机验收通过。**

真实限制如下：
1. **本阶段未构建整包 APK**：
   - 遵照指令限制，本轮仅处理原生库与构建配置，未执行 `flutter build apk`，现有根目录下 `eir-v1.0.40.apk` 仍为前序版本产物，尚未打包本次新生成的 16KB 对齐原生库。
2. **本阶段未执行设备安装与运行**：
   - 未向连接的 ADB 设备推送安装新 APK，未改动 ADB 状态或应用数据。
3. **未在物理 16KB 硬件上运行**：
   - 当前实测环境为 Linux x86_64 宿主机与 x86_64 虚拟设备，16KB 对齐通过 ELF 程序头的严格静态度量验证；在具备 16KB 页内核的三星或 Pixel Android 15 设备上的动态 `dlopen` 运行，有待后续整包构建与双端真实验收。
4. **未发布**：
   - 未向任何商店、GitHub Releases 或 Yggdrasil 平台提交发布。
