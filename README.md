# 悦高清 · yue-hidpi

[![CI](https://github.com/hummerstudio/yue-hidpi/actions/workflows/ci.yml/badge.svg)](https://github.com/hummerstudio/yue-hidpi/actions/workflows/ci.yml)

让 Mac 用上 HiDPI 缩放的一条命令。macOS 只在"视网膜屏"上默认开放 HiDPI，外接显示器插上来往往只有原始分辨率，字细、图标糊。这个工具把社区脚本里那套手工流程做成一个可审计、可回滚的命令行程序。

```
$ yue-hidpi list
  #  显示器                   类型  面板像素   当前模式  HiDPI
  0  Built-in Retina Display  内置  2880×1800  1440×900  ✔

[0] Built-in Retina Display  displayID=69734272  610:a03e
    可用 HiDPI 逻辑分辨率: 1680 × 1050 · 1440 × 900 · 1280 × 800 · 1024 × 640
    共 17 个模式（其中 1x 模式 11 个）
```

```
$ sudo yue-hidpi enable            # 安装档位 + 打开总开关，然后注销
$ yue-hidpi set 1600x900           # 登录后切到想要的缩放
$ yue-hidpi status                 # 随时查看：装了没、生效没
全局开关
  DisplayResolutionEnabled = 已开启
  覆盖目录: /Library/Displays/Contents/Resources/Overrides
  清单文件: /Library/Application Support/yue-hidpi/manifest.json

  #  显示器                   覆盖文件  档位数  当前 HiDPI
  0  Built-in Retina Display  已安装    4       ✔
```

- **不关 SIP，不 patch 系统文件，不调私有 API**：只写 Apple 自己使用的两个公开位置，并全程留清单。
- **自动推算档位**：读取面板像素与型号（vendor/product），按宽高比给出候选分辨率，超出面板的会明确告警。
- **可回滚**：`disable --all` 移除覆盖文件、还原备份、恢复原来的 `DisplayResolutionEnabled` 取值。
- **可验证**：`selftest` 校验字节格式与安装/还原路径，`set` 切换后会回读当前模式而不是相信返回码。

## 为什么是 Swift，不是 Go

这不是口味问题，取决于要调的 API：

| | Swift | Go |
| --- | --- | --- |
| CoreGraphics 显示模式枚举/切换 | 直接链接 `CGDisplayCopyAllDisplayModes` / `CGConfigureDisplayWithDisplayMode` | 需要 cgo 手写绑定 |
| EDID / IOKit / 私有 CoreDisplay 兜底 | 原生可用 | dlopen + 函数指针，类型全靠手写 |
| 产物 | 单一可执行文件，系统自带 Swift 运行时，用户零依赖 | 单一可执行文件，同样零依赖 |
| 交叉架构 | `swift build --arch arm64 --arch x86_64` + `lipo` | 更简单，但 macOS-only 场景用不上 |

结论：只要工具需要**枚举显示模式、判断某个模式是不是 2x backing、按显示器切换模式**，Swift 就是省掉一整层 cgo 的唯一选择。Go 的优势（跨平台交叉编译、部署简单）在"只跑 macOS、只调 macOS 私有显示栈"的场合没有价值。

## 它做了什么

macOS 的 HiDPI 由三件事共同决定，缺一不可：

1. **覆盖文件**：`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor>/DisplayProductID-<product>`
   列表里声明该型号额外支持的 *像素* 分辨率，HiDPI 档位用 `0x00200000` 标记。格式见 [docs/override-format.md](docs/override-format.md)，与 Apple 自带文件逐字节对齐。
2. **总开关**：`/Library/Preferences/com.apple.windowserver` 的 `DisplayResolutionEnabled = true`。
3. **WindowServer 重载**：注销/重启，或 `sudo killall -HUP WindowServer`（会关掉所有 App，所以默认不自动做）。

`set` 之后走的是公开 API：`CGBeginDisplayConfiguration` → `CGConfigureDisplayWithDisplayMode` → `CGCompleteDisplayConfiguration(.permanently)`，并用 `CGDisplayCopyDisplayMode` 回读确认。

## 安装

要求 macOS 11+，以及 Xcode 或 Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/hummerstudio/yue-hidpi.git
cd yue-hidpi
make build                 # 本机架构
# 或 make universal        # arm64 + x86_64 一个文件，适合分发
sudo make install          # → /usr/local/bin/yue-hidpi
```

不想编译：直接取 [Releases](https://github.com/hummerstudio/yue-hidpi/releases) 里的 universal 二进制（arm64 + x86_64，macOS 11+ 直接跑，不需要装 Swift 运行时）。

```bash
curl -fsSL -o /usr/local/bin/yue-hidpi \
  https://github.com/hummerstudio/yue-hidpi/releases/latest/download/yue-hidpi
chmod +x /usr/local/bin/yue-hidpi
yue-hidpi list
```

**关于架构与 Swift 运行时**

- Swift 运行时自 macOS 10.14.4 起就是系统的一部分（`/usr/lib/swift/*` 由 dyld 共享缓存提供，不是磁盘上的实体文件）。`otool -L` 显示的 `/usr/lib/swift/libswiftCore.dylib` 由系统解析，**用户不需要安装任何运行时**。
- 在 Intel Mac 上 `make build` 只产出 x86_64 二进制，拷到 Apple Silicon 上要靠 Rosetta 2 运行（系统会提示安装，纯命令行场景不总是顺手）。
- 要原生跑 arm64，用 `make universal`：项目用 `swift build --triple arm64-apple-macosx11.0` 交叉编译再用 `lipo` 合并，只装 Command Line Tools 也能完成，不依赖完整 Xcode。
- 发布到 GitHub Releases 的二进制应当是 universal，README 顶部下载链接也指向它。

没有 Homebrew formula：这个工具会改显示配置，作者倾向于让用户看着源码装。欢迎补 formula。

> 主仓在 GitHub；GitCode `yuetool/yue-hidpi`（悦兔AI 组）是同步镜像。

## 用法

| 命令 | 作用 |
| --- | --- |
| `yue-hidpi list` | 显示器、面板像素、当前模式、已可用的 HiDPI 档位；`--all-modes` 列全部，`--json` 给脚本 |
| `yue-hidpi status` | 覆盖文件是否安装、是否本工具装的、总开关状态、哪些档位还没生效 |
| `yue-hidpi generate --out DIR` | 只生成 plist，不碰系统（也不提权），适合先看再装 |
| `yue-hidpi enable` | 生成并安装覆盖文件 + 打开 `DisplayResolutionEnabled` |
| `yue-hidpi disable --all` | 移除本工具装的文件、还原备份、恢复总开关原值 |
| `yue-hidpi set 1600x900` | 切到某个 HiDPI 逻辑分辨率，并回读验证 |
| `yue-hidpi doctor` | 环境自检：权限、目录、开关、每块屏的档位是否真的生效 |
| `yue-hidpi selftest` | 18 项内置不变量检查，不需要 Xcode |

常用组合：

```bash
# 只想给外接屏加档位，指定分辨率
sudo yue-hidpi enable --display 1 --res 1920x1080,1680x945,1600x900

# 先看会写什么（XML 全文），确认后再装
yue-hidpi enable --diff

# 演练：完全不碰系统，写到临时根目录
yue-hidpi enable --root /tmp/yue-demo

# 装完不想注销，立刻生效（会关闭所有 App）
sudo yue-hidpi enable --restart-windowserver
```

`--display` 既可以接 `list` 第一列的序号，也可以接 `CGDirectDisplayID`。多显示器可以逗号分隔。

## 会改动哪些文件

| 路径 | 用途 | 回滚方式 |
| --- | --- | --- |
| `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-*/DisplayProductID-*` | 档位声明 | `disable --all`（若原本存在同名文件，会先备份为 `*.yue-hidpi.bak` 并在移除时还原） |
| `/Library/Preferences/com.apple.windowserver` → `DisplayResolutionEnabled` | 总开关 | 记录安装前的取值，移除后恢复；原本没有这个键则删掉 |
| `/Library/Application Support/yue-hidpi/manifest.json` | 记账：装了哪些文件、备份在哪、开关原值 | 记录清空后自动删除 |

除此之外不写任何位置。

## 已知限制

诚实列出，避免预期落空：

- **本机实测环境**：Intel MacBook Pro（Iris Plus 655）+ macOS 15.8，内置 Retina 屏。外接显示器、Apple Silicon 上的表现作者尚未在同一台机器上验证，不做承诺。
- **Apple Silicon / macOS 14+ 的部分版本会忽略 `/Library` 覆盖文件**（社区长期反馈）。此时 `doctor` 会明确报"档位已生效 ✘"，而不是假装成功。真遇到需要额外手段（例如 `DisplayProductID` 之外的系统级 patch），本工具不越界。
- **必须重载 WindowServer**：不注销不会出现新档位。`set` 在档位缺失时会提示原因，不会静默失败。
- **超采样档位会掉清晰度**：在 4K 上开 `2560x1440`（渲染 5120×2880 再缩放）会明显更累 GPU。工具会打印告警，但不会阻止你。
- **同型号两块屏共用一个 plist**：这是 Apple 的键设计（vendor/product 不含序列号），不是本工具的选择。`enable` 会把两块屏的档位并集写进同一个文件。
- 内置 Retina 屏本身已有 HiDPI，`enable` 对它基本是空操作，属预期。

## 常见问题

**`set` 报"没有 1600x900 的 HiDPI 档位"**
`enable` 之后没有注销。先注销重登（或 `sudo killall -HUP WindowServer`），再 `yue-hidpi status` 确认档位已被系统识别。

**装完系统设置里没变化**
macOS 15 的"显示器"面板只列系统认可的档位；`yue-hidpi list` 列的是真实可切换的模式。两者不一致时以 `list` / `status` 为准。

**`disable` 之后要不要注销**
要。移除同样需要 WindowServer 重载才回到原状。

**和 displayplacer / SwitchResX 冲突吗**
不冲突，定位不同：它们负责"切换已存在的模式"，本工具负责"让系统先拥有这些模式"。可以先用本工具造档位，再用 displayplacer 做快捷切换。

## 开发

```bash
make selftest   # 只需 Command Line Tools，18 项不变量检查
make test       # XCTest，需要完整 Xcode（CI 用）
make universal  # 生成 arm64 + x86_64 通用二进制
```

```
Sources/YueHiDPICore/     核心：模式枚举、plist 编码、安装/回滚、档位推算、自检
Sources/yue-hidpi/        CLI：参数解析、输出、提权
Tests/YueHiDPICoreTests/  XCTest 包装 SelfTest + plist 合法性
docs/override-format.md   覆盖文件字节格式与 Apple 自带文件的交叉验证
```

设计上把"决定写什么字节"和"写到哪里"分开：`OverrideDocument` 是纯数据，`Installer` 通过 `Paths(root:)` 接受任意根目录，所以整条安装/回滚链路都能在临时目录里跑完，不需要 sudo 也不污染系统。`--root` 就是这么来的。

## License

MIT © 2026 唐莫盈

---

### English

`yue-hidpi` is a macOS CLI that enables HiDPI scaling on non-Retina displays. It writes the same `scale-resolutions` override plists Apple ships, flips `DisplayResolutionEnabled`, and switches modes through public CoreGraphics APIs. Written in Swift because the core needs `CGDisplayCopyAllDisplayModes` / `CGConfigureDisplayWithDisplayMode` — Go would require cgo and private-framework plumbing.

Tested on Intel MacBook Pro + macOS 15.8. Every installed file is tracked in a manifest and fully revertible with `yue-hidpi disable --all`.
