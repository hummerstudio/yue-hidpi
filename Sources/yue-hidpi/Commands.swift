import CoreGraphics
import Foundation
import YueHiDPICore

// MARK: - list

enum CommandList {
    static func run(_ args: Arguments) -> Int32 {
        let displays = DisplayEnumerator.all()
        guard !displays.isEmpty else {
            fail("没有检测到在线显示器")
        }

        if args.flag("--json") {
            emit(Json.encode(displays.enumerated().map { index, display in
                DisplayReport(index: index, display: display)
            }))
            return 0
        }

        var table = Table(headers: ["#", "显示器", "类型", "面板像素", "当前模式", "HiDPI"])
        for (index, display) in displays.enumerated() {
            table.add([
                "\(index)",
                display.name,
                display.isBuiltin ? "内置" : (display.isMain ? "主屏" : "外接"),
                "\(display.panelPixelWidth)×\(display.panelPixelHeight)",
                display.current.map { "\($0.width)×\($0.height)" } ?? "未知",
                display.isCurrentlyHiDPI ? Ansi.green("✔") : Ansi.yellow("✘")
            ])
        }
        emit(table.render(headerColor: Ansi.bold))
        emit("")
        for (index, display) in displays.enumerated() {
            emit(Ansi.bold("[\(index)] \(display.name)") + Ansi.dim("  displayID=\(display.id)  \(display.vendorHex):\(display.productHex)"))
            let hiDPI = display.availableHiDPISizes
            if hiDPI.isEmpty {
                emit("    当前没有 HiDPI 档位 → " + Ansi.yellow("运行 `\(toolName) enable` 生成后注销"))
            } else {
                emit("    可用 HiDPI 逻辑分辨率: " + hiDPI.map(\.label).joined(separator: " · "))
            }
            let plain = display.modes.filter { !$0.isHiDPI }.count
            emit(Ansi.dim("    共 \(display.modes.count) 个模式（其中 1x 模式 \(plain) 个）"))
            if args.flag("--all-modes") {
                for mode in display.modes {
                    let mark = mode.isCurrent ? "*" : " "
                    emit("     \(mark) \(Text.pad(mode.label, 22)) \(String(format: "%.0fHz", mode.refreshRate))")
                }
            }
            emit("")
        }
        return 0
    }
}

struct DisplayReport: Encodable {
    let index: Int
    let id: UInt32
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let isBuiltin: Bool
    let isMain: Bool
    let panel: Size2D
    let current: ModeInfo?
    let isHiDPI: Bool
    let availableHiDPISizes: [Size2D]
    let modeCount: Int

    init(index: Int, display: DisplayInfo) {
        self.index = index
        self.id = display.id
        self.name = display.name
        self.vendorID = display.vendorID
        self.productID = display.productID
        self.isBuiltin = display.isBuiltin
        self.isMain = display.isMain
        self.panel = display.panelSize
        self.current = display.current
        self.isHiDPI = display.isCurrentlyHiDPI
        self.availableHiDPISizes = display.availableHiDPISizes
        self.modeCount = display.modes.count
    }
}

// MARK: - status

enum CommandStatus {
    static func run(_ args: Arguments) -> Int32 {
        let paths = Paths(root: args.option("--root") ?? "/")
        let displays = DisplayEnumerator.all()
        let manifest = Installer.loadManifest(paths: paths)
        let flag = WindowServerFlag.read()

        if args.flag("--json") {
            emit(Json.encode(StatusReport(
                displayResolutionEnabled: flag,
                overridesDirectory: paths.overridesDirectory,
                manifestPath: manifest.records.isEmpty ? nil : paths.manifestFile,
                displays: displays.enumerated().map { index, display in
                    DisplayStatus(index: index,
                                  display: display,
                                  paths: paths,
                                  record: manifest.record(forDisplay: display.id))
                }
            )))
            return 0
        }

        emit(Ansi.bold("全局开关"))
        switch flag {
        case .some(true): emit("  DisplayResolutionEnabled = " + Ansi.green("已开启"))
        case .some(false): emit("  DisplayResolutionEnabled = " + Ansi.yellow("已关闭") + Ansi.dim("（覆盖文件不会生效）"))
        case .none: emit("  DisplayResolutionEnabled = " + Ansi.dim("未设置（等同关闭）"))
        }
        emit(Ansi.dim("  覆盖目录: \(paths.overridesDirectory)"))
        if !manifest.records.isEmpty {
            emit(Ansi.dim("  清单文件: \(paths.manifestFile)"))
        }
        emit("")

        var table = Table(headers: ["#", "显示器", "覆盖文件", "档位数", "当前 HiDPI"])
        for (index, display) in displays.enumerated() {
            let record = manifest.record(forDisplay: display.id)
            let exists = Installer.hasOverride(for: display, paths: paths)
            let sizeCount = record?.sizes.count ?? (Installer.installedSizes(plistPath: Installer.overridePath(for: display, paths: paths)).flatMap { $0 }?.count ?? 0)
            table.add([
                "\(index)",
                display.name,
                exists ? (record != nil ? Ansi.green("已安装") : Ansi.yellow("存在(非本工具)")) : Ansi.dim("无"),
                "\(sizeCount)",
                display.isCurrentlyHiDPI ? Ansi.green("✔") : Ansi.yellow("✘")
            ])
        }
        emit(table.render(headerColor: Ansi.bold))

        let pending = displays.filter { display in
            let declared = Installer.installedSizes(plistPath: Installer.overridePath(for: display, paths: paths)) ?? []
            return !declared.isEmpty && declared.isDisjoint(with: Set(display.availableHiDPISizes))
        }
        if !pending.isEmpty {
            emit("")
            emit(Ansi.yellow("有待生效的覆盖：") + pending.map(\.name).joined(separator: "、"))
            emit(Ansi.dim("  注销并重新登录即可生效，或运行 `sudo killall -HUP WindowServer`（会关闭所有 App）"))
        }
        return 0
    }
}

struct DisplayStatus: Encodable {
    let index: Int
    let id: UInt32
    let name: String
    let overrideInstalled: Bool
    let managedByTool: Bool
    let declaredSizes: [Size2D]
    let availableHiDPISizes: [Size2D]
    let isHiDPI: Bool

    init(index: Int, display: DisplayInfo, paths: Paths, record: InstalledRecord?) {
        self.index = index
        self.id = display.id
        self.name = display.name
        self.overrideInstalled = Installer.hasOverride(for: display, paths: paths)
        self.managedByTool = record != nil
        self.declaredSizes = record?.sizes
            ?? (Installer.installedSizes(plistPath: Installer.overridePath(for: display, paths: paths)).map { Array($0) } ?? [])
        self.availableHiDPISizes = display.availableHiDPISizes
        self.isHiDPI = display.isCurrentlyHiDPI
    }
}

struct StatusReport: Encodable {
    let displayResolutionEnabled: Bool?
    let overridesDirectory: String
    let manifestPath: String?
    let displays: [DisplayStatus]
}

// MARK: - generate

enum CommandGenerate {
    static func run(_ args: Arguments) -> Int32 {
        let paths = Paths(root: args.option("--root") ?? "/")
        let displays = DisplayEnumerator.all()
        let selected = args.selectedDisplayIDs(from: displays)
        guard !selected.isEmpty else { fail("没有匹配的显示器，先运行 `\(toolName) list`") }

        let groups = OverridePlanner.plan(displays: selected, paths: paths, resolutions: args.option("--res"))
        let outputDirectory = args.option("--out") ?? "\(paths.overridesDirectory)"

        do {
            for warning in groups.warnings { emit(Ansi.yellow("注意: ") + warning) }
            if !groups.warnings.isEmpty { emit("") }
            for group in groups.groups {
                let data = try group.document.xmlData()
                let target = (outputDirectory as NSString).appendingPathComponent(group.document.relativePath)
                try FileManager.default.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                                        withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: target), options: .atomic)
                emit(Ansi.green("✔ ") + target)
                emit(Ansi.dim("  \(group.document.logicalSizes.map(\.label).joined(separator: " · "))"))
            }
            emit("")
            emit(Ansi.dim("plist 只描述档位，需要放进 \(Paths(root: "/").overridesDirectory) 并注销后才生效。"))
            emit(Ansi.dim("安装请用 `\(toolName) enable`，或手动执行：sudo cp -R <上面的目录>/DisplayVendorID-* \(Paths(root: "/").overridesDirectory)/"))
        } catch {
            fail("生成失败：\(error.localizedDescription)")
        }
        return 0
    }
}

// MARK: - enable

enum CommandEnable {
    static func run(_ args: Arguments) -> Int32 {
        let paths = Paths(root: args.option("--root") ?? "/")
        let displays = DisplayEnumerator.all()
        let selected = args.selectedDisplayIDs(from: displays)
        guard !selected.isEmpty else { fail("没有匹配的显示器，先运行 `\(toolName) list`") }

        let plan = OverridePlanner.plan(displays: selected, paths: paths, resolutions: args.option("--res"))
        guard !plan.groups.isEmpty else { fail("没有生成任何覆盖文件") }

        if args.flag("--diff") {
            for group in plan.groups {
                emit(Ansi.bold("# \(group.document.relativePath)"))
                if let text = try? group.document.xmlData(), let xml = String(data: text, encoding: .utf8) {
                    emit(xml)
                }
            }
            return 0
        }

        // Writing under /Library and touching WindowServer prefs both need root.
        // A custom --root is a rehearsal, so it never elevates.
        let needsRoot = paths.root.isEmpty
        if needsRoot && !Privilege.isRoot {
            do { try Privilege.elevate(arguments: Array(CommandLine.arguments.dropFirst())) }
            catch { fail("提权失败：\(error.localizedDescription)") }
        }

        for warning in plan.warnings { emit(Ansi.yellow("注意: ") + warning) }
        if !plan.warnings.isEmpty { emit("") }

        do {
            let results = try Installer.install(targets: plan.installTargets(), paths: paths)

            emit(Ansi.bold("覆盖文件"))
            for result in results {
                emit(Ansi.green("  ✔ ") + result.path)
                emit(Ansi.dim("    \(result.sizes.map(\.label).joined(separator: " · "))"))
                if result.replacedPreviousFile {
                    emit(Ansi.dim("    已替换原有文件（原文件如有内容已备份为 *.yue-hidpi.bak）"))
                }
            }

            if needsRoot {
                var manifest = Installer.loadManifest(paths: paths)
                if !manifest.displayResolutionEnabledTouched {
                    manifest.previousDisplayResolutionEnabled = WindowServerFlag.read()
                    manifest.displayResolutionEnabledTouched = true
                    try Installer.saveManifest(manifest, paths: paths)
                }
                try WindowServerFlag.write(true)
                emit(Ansi.green("\n✔ 已开启 DisplayResolutionEnabled"))
            }

            emit("")
            emit(Ansi.bold("下一步"))
            emit("  1. 注销并重新登录（推荐；重启也行）")
            emit("     也可以立刻生效，但会关闭所有 App：'sudo killall -HUP WindowServer'")
            emit("  2. 登录后执行：'\(toolName) set \(plan.preferredSizeLabel ?? "1600x900")'")

            if args.flag("--restart-windowserver") && needsRoot {
                emit("\n正在重启 WindowServer…")
                try WindowServer.restart()
                emit(Ansi.green("✔ WindowServer 已重启，档位应当已生效"))
            }
        } catch {
            fail("安装失败：\(error.localizedDescription)")
        }
        return 0
    }
}

// MARK: - disable

enum CommandDisable {
    static func run(_ args: Arguments) -> Int32 {
        let paths = Paths(root: args.option("--root") ?? "/")
        let displays = DisplayEnumerator.all()
        let selected = args.selectedDisplayIDs(from: displays)
        let manifest = Installer.loadManifest(paths: paths)
        let ids: [UInt32] = args.flag("--all") || args.option("--display") == nil
            ? []
            : selected.map(\.id)

        if manifest.records.isEmpty {
            emit(Ansi.dim("没有由 \(toolName) 安装的覆盖文件，无需处理。"))
            return 0
        }

        let needsRoot = paths.root.isEmpty
        if needsRoot && !Privilege.isRoot {
            do { try Privilege.elevate(arguments: Array(CommandLine.arguments.dropFirst())) }
            catch { fail("提权失败：\(error.localizedDescription)") }
        }

        do {
            let removed = try Installer.remove(displayIDs: ids, paths: paths)
            if removed.isEmpty {
                emit(Ansi.dim("没有匹配的覆盖文件。"))
                return 0
            }
            for item in removed {
                emit(Ansi.green("  ✔ 已移除 ") + item.path + (item.restoredBackup ? Ansi.dim("（已还原备份）") : ""))
            }

            var updated = Installer.loadManifest(paths: paths)
            if updated.records.isEmpty && updated.displayResolutionEnabledTouched {
                if let previous = updated.previousDisplayResolutionEnabled {
                    try WindowServerFlag.write(previous)
                    emit(Ansi.dim("  已把 DisplayResolutionEnabled 还原为 \(previous ? "开启" : "关闭")"))
                } else {
                    Shell.run("/usr/bin/defaults", ["delete", WindowServerFlag.domain, WindowServerFlag.key])
                    emit(Ansi.dim("  已清除 DisplayResolutionEnabled（恢复系统默认）"))
                }
                updated.displayResolutionEnabledTouched = false
                updated.previousDisplayResolutionEnabled = nil
                if updated.records.isEmpty {
                    // Nothing left to track: do not leave an empty manifest behind.
                    try? FileManager.default.removeItem(atPath: paths.manifestFile)
                } else {
                    try Installer.saveManifest(updated, paths: paths)
                }
            }

            emit("")
            emit(Ansi.dim("注销后生效。"))
        } catch {
            fail("移除失败：\(error.localizedDescription)")
        }
        return 0
    }
}

// MARK: - set

enum CommandSet {
    static func run(_ args: Arguments) -> Int32 {
        guard let raw = args.positionals.first, let target = Size2D(string: raw) else {
            fail("用法: \(toolName) set <宽x高> [--display N]   例如 \(toolName) set 1600x900", code: 2)
        }
        let displays = DisplayEnumerator.all()
        let selected = args.selectedDisplayIDs(from: displays)
        guard !selected.isEmpty else { fail("没有匹配的显示器") }

        var failures: [String] = []
        var applied = 0

        for display in selected {
            guard let mode = DisplayEnumerator.modeRef(display.id, matching: target, hiDPI: true) else {
                let available = display.availableHiDPISizes.map(\.label)
                failures.append(available.isEmpty
                    ? "\(display.name)：当前没有任何 HiDPI 档位，先运行 `\(toolName) enable` 并注销"
                    : "\(display.name)：没有 \(target.label) 的 HiDPI 档位。可用：\(available.joined(separator: " / "))")
                continue
            }
            var configuration: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration = configuration else {
                failures.append("\(display.name)：无法创建显示配置")
                continue
            }
            let configured = CGConfigureDisplayWithDisplayMode(configuration, display.id, mode, nil)
            guard configured == .success else {
                CGCancelDisplayConfiguration(configuration)
                failures.append("\(display.name)：设置模式被系统拒绝")
                continue
            }
            let committed = CGCompleteDisplayConfiguration(configuration, .permanently)
            guard committed == .success else {
                failures.append("\(display.name)：提交配置失败（code \(committed.rawValue)）")
                continue
            }
            // Read back instead of trusting the return code.
            let current = CGDisplayCopyDisplayMode(display.id).map { ModeInfo(cgMode: $0, isCurrent: true) }
            if current?.size == target && current?.isHiDPI == true {
                emit(Ansi.green("✔ ") + "\(display.name) → \(target.label) HiDPI")
                applied += 1
            } else {
                failures.append("\(display.name)：切换后回读为 \(current?.label ?? "未知")，未生效")
            }
        }

        if !failures.isEmpty {
            for message in failures { emit(Ansi.yellow("注意: ") + message) }
        }
        if applied == 0 { return 1 }
        emit(Ansi.dim("已保存到系统显示配置，重新登录后保持。"))
        return 0
    }
}

// MARK: - selftest

enum CommandSelfTest {
    static func run(_ args: Arguments) -> Int32 {
        let results = SelfTest.run()
        if args.flag("--json") {
            emit(Json.encode(results))
            return results.allSatisfy(\.passed) ? 0 : 1
        }
        var table = Table(headers: ["结果", "检查项", "实测"])
        for result in results {
            table.add([result.passed ? Ansi.green("✔") : Ansi.red("✘"), result.name, result.detail])
        }
        emit(table.render(headerColor: Ansi.bold))
        let failed = results.filter { !$0.passed }
        emit("")
        if failed.isEmpty {
            emit(Ansi.green("\(results.count) 项全部通过。"))
            return 0
        }
        emit(Ansi.red("\(failed.count)/\(results.count) 项失败：") + failed.map(\.name).joined(separator: "、"))
        return 1
    }
}

// MARK: - doctor

enum CommandDoctor {
    static func run(_ args: Arguments) -> Int32 {
        let paths = Paths(root: args.option("--root") ?? "/")
        let displays = DisplayEnumerator.all()
        var problems = 0

        func check(_ ok: Bool, _ label: String, detail: String, hint: String? = nil, warnOnly: Bool = false) {
            let mark = ok ? Ansi.green("✔") : (warnOnly ? Ansi.yellow("!") : Ansi.red("✘"))
            emit("\(mark) \(label)" + (detail.isEmpty ? "" : Ansi.dim("  " + detail)))
            if !ok {
                if !warnOnly { problems += 1 }
                if let hint = hint { emit("    → " + hint) }
            }
        }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        emit(Ansi.bold("环境"))
        check(version.majorVersion >= 11, "macOS 版本", detail: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        check(true, "架构", detail: architecture())
        check(displays.count > 0, "在线显示器", detail: "\(displays.count) 台")

        emit("")
        emit(Ansi.bold("覆盖目录"))
        let overridesExists = FileManager.default.fileExists(atPath: paths.overridesDirectory)
        check(overridesExists, "覆盖目录",
              detail: paths.overridesDirectory + (overridesExists ? "" : "（尚未创建）"),
              hint: "运行 `\(toolName) enable` 会自动创建", warnOnly: true)

        emit("")
        emit(Ansi.bold("全局开关"))
        switch WindowServerFlag.read() {
        case .some(true): check(true, "DisplayResolutionEnabled", detail: "已开启")
        case .some(false): check(false, "DisplayResolutionEnabled", detail: "已关闭", hint: "运行 `\(toolName) enable`", warnOnly: true)
        case .none: check(false, "DisplayResolutionEnabled", detail: "未设置（等同关闭）", hint: "运行 `\(toolName) enable`", warnOnly: true)
        }

        emit("")
        emit(Ansi.bold("显示器"))
        for display in displays {
            let installed = Installer.installedSizes(plistPath: Installer.overridePath(for: display, paths: paths))
            let available = display.availableHiDPISizes
            emit("  " + Ansi.bold(display.name))
            check(display.panelPixelWidth > 0, "面板像素", detail: "\(display.panelPixelWidth)×\(display.panelPixelHeight)")
            check(true, "当前模式", detail: display.current?.label ?? "未知")
            check(display.isCurrentlyHiDPI, "当前是 HiDPI", detail: display.isCurrentlyHiDPI ? "是" : "否",
                  hint: "运行 `\(toolName) enable` 后注销，再 `\(toolName) set <宽x高>`", warnOnly: true)
            if let installed = installed {
                check(true, "声明档位", detail: installed.map(\.label).sorted().joined(separator: " · "))
                let effective = !installed.isDisjoint(with: Set(available))
                check(effective, "档位已生效", detail: effective ? "是" : "否",
                      hint: "注销重新登录，或 `sudo killall -HUP WindowServer`")
            } else {
                check(true, "覆盖文件", detail: "无", warnOnly: true)
            }
        }

        emit("")
        if problems == 0 {
            emit(Ansi.green("未发现问题。"))
        } else {
            emit(Ansi.yellow("发现 \(problems) 个问题，见上面的 → 提示。"))
        }
        return problems == 0 ? 0 : 1
    }

    static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
