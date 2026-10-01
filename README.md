# MCBEforMacOS-CodeHub

在 macOS(x86_64)上运行《我的世界》基岩版 **Windows GDK 版** 所需的**全量自包含运行时**,以 NuGet 包 `CodeHub.MCBEforMacOS` 分发。

## 组成

| 目录 | 内容 | 作用 |
| --- | --- | --- |
| `wine/` | [Weather-OS/WineGDK](https://github.com/Weather-OS/WineGDK) 构建出的 Wine 安装树 | 承载 Windows PE 程序;其中 `dlls/xgameruntime` 提供 Xbox GDK 组件与可用的 XUser 实现 |
| `xodus/` | [xodus-gaming/xodus](https://github.com/xodus-gaming/xodus) 的 `xodus-service`(原生 macOS 进程) | 承担 MSA 登录、XSTS 授权、许可获取等需要联网的能力 |
| `render/` | MoltenVK + DXVK + vkd3d-proton | Vulkan 实现与 D3D → Vulkan 转换层 |

## 工作机制

```
   ┌──────────────────────── macOS 进程 ────────────────────────┐
   │                                                            │
   │  Minecraft.Windows.exe (PE, x86_64)                        │
   │        │                                                   │
   │        │ 调用 XUser* API                                    │
   │        ▼                                                   │
   │  xgameruntime.dll  (PE 侧, wine/lib/wine/x86_64-windows)   │
   │        │  __wine_load_unix_lib("xgameruntime.so")           │
   │        ▼                                                   │
   │  xgameruntime.so   (unix 侧, wine/lib/wine/x86_64-unix)     │
   │        │  AF_UNIX 连接 /tmp/xodus.sock                      │
   │        ▼                                                   │
   │  xodus-service     (原生 macOS 可执行文件)                   │
   │        └──► Microsoft MSA / XSTS / 许可服务                 │
   └────────────────────────────────────────────────────────────┘
```

### Xodus IPC 契约

两侧必须严格一致,上游实现如下(勿改动):

- socket 路径:`/tmp/xodus.sock`
  - unix 侧:`GDKComponent/Xodus/Unix/socket.c` 在 `__APPLE__` 下取 `/tmp`;Linux 下取 `$XDG_RUNTIME_DIR`
  - 服务侧:`crates/xodus-service/src/utils.rs` 的 `get_runtime_dir()` 在 `target_os = "macos"` 下返回 `/tmp/`
- 帧格式:`magic(u32 LE) + msg_type(u16) + len(u16) + body`
  - `XML_MAGIC = 0x58445358`(`"XDSX"`)
  - `PROTO_MAGIC = 0x58445350`(`"XDS P"`)
- socket 权限 `0600`,由服务侧创建并在退出时删除

## 构建

全部构建走 GitHub Actions(公开仓库免费),本机不参与构建。

- `.github/workflows/build.yml`
  - `xodus-service` 任务:macOS Intel runner 上 `cargo build --release -p xodus-service`
  - `render-stack` 任务:下载 MoltenVK/DXVK/vkd3d-proton 官方 Release
  - `runtime` 任务:构建 Wine(WineGDK,x86_64)→ 汇总 → `dotnet pack` → 产出 `.nupkg`
  - `publish` 任务:`main` 分支与 `v*` 标签推送到 GitHub Packages

Wine 构建配方对齐上游 `tools/gitlab/build-mac`:

```
./tools/make_requests && ./tools/make_specfiles && ./tools/make_makefiles && autoreconf -f
../configure -C --enable-win64 --with-mingw ...
make -j
make install DESTDIR=<stage>
```

上游把 libxml2 以 PE 静态库的形式内置在 `libs/xml2`(`WINE_EXTLIB_FLAGS(XML2, xml2, xml2, ...)`),
因此**无需**为 mingw 交叉编译 libxml2,只要 `mingw-w64` 工具链在 `PATH` 中即可。

runner 选用 `macos-15-intel`(`macos-13` 已于 2025-12-04 退役),因此 PE 代码由 Intel CPU 原生执行,不依赖 Rosetta 2。

## 使用

```xml
<PackageReference Include="CodeHub.MCBEforMacOS" Version="0.1.0-dev.*" />
```

包会把运行时放在 `runtimes/osx-x64/native/`。**NuGet 解包会丢失可执行位**,因此不要把包内文件直接拿来执行;
在消费工程里打开 Stage 目标,让 MSBuild 复制并修复权限:

```xml
<PropertyGroup>
  <McbeMacOSStageRuntime>true</McbeMacOSStageRuntime>
</PropertyGroup>
```

随后运行时位于 `$(OutDir)mcbe-macos/`,`McbeMacOSRuntime.Locate()` 会自动发现它。
也可以设置环境变量 `MCBE_MACOS_RUNTIME_DIR` 指向任意位置。

```csharp
using CodeHub.MCBEforMacOS;

var runtime = McbeMacOSRuntime.Locate() ?? throw new InvalidOperationException("未找到运行时");
await using var xodus = new XodusServiceHost(runtime.XodusServiceBinary);
await xodus.StartAsync();

var startInfo = WineEnvironment.CreateStartInfo(
    runtime,
    prefixPath: Path.Combine(home, "Library/Application Support/MChub/Bedrock/wine-prefix"),
    executable: Path.Combine(instancePath, "Minecraft.Windows.exe"),
    arguments: null,
    workingDirectory: instancePath);
```

## 已知限制

- 仅 x86_64:依赖 Intel runner 与 Intel Mac;Rosetta 2 退场(约 2027 秋)后需改走 arm64 Wine + 交叉执行。
- Apple Game Porting Toolkit 的 **D3DMetal 不可再分发**,不在包内;需要它的用户自行安装 GPTK。包内使用 MoltenVK + DXVK/vkd3d-proton。
- `xodus-service` 首次运行会在 macOS 钥匙串中写入设备凭据,可能需要用户授权。
- Wine 部分取自 Weather-OS/WineGDK,该分支并非上游 Wine 官方版本,行为与官方构建存在差异。

## 许可

本仓库自身的胶水代码随仓库许可分发;`wine/`、`xodus/`、`render/` 内各组件保留其原始许可,
相关许可文本见各目录中的 `LICENSE*` 与 `render/licenses/`。