import Foundation
import YueHiDPICore

let toolName = "yue-hidpi"
let toolVersion = "0.1.0"

// MARK: - Argument parsing

struct Arguments {
    var command: String = ""
    var positionals: [String] = []
    var flags: Set<String> = []
    var options: [String: String] = [:]

    static let valueOptions: Set<String> = ["--display", "--res", "--out", "--root", "--scale"]

    func flag(_ name: String) -> Bool { flags.contains(name) }
    func option(_ name: String) -> String? { options[name] }

    /// `--display 1` (CGDirectDisplayID) or `--display 0` (index in `list` output).
    func selectedDisplayIDs(from displays: [DisplayInfo]) -> [DisplayInfo] {
        guard let raw = option("--display") else { return displays }
        let tokens = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [DisplayInfo] = []
        for token in tokens {
            if let id = UInt32(token), let match = displays.first(where: { $0.id == id }) {
                result.append(match)
            } else if let index = Int(token), index >= 0, index < displays.count {
                result.append(displays[index])
            }
        }
        return result
    }
}

func parseArguments(_ argv: [String]) -> Arguments {
    var args = Arguments()
    var index = 0
    while index < argv.count {
        let token = argv[index]
        if token.hasPrefix("--") {
            if let equals = token.firstIndex(of: "=") {
                let key = String(token[..<equals])
                args.options[key] = String(token[token.index(after: equals)...])
            } else if Arguments.valueOptions.contains(token) {
                if index + 1 < argv.count {
                    args.options[token] = argv[index + 1]
                    index += 1
                }
            } else {
                args.flags.insert(token)
            }
        } else if args.command.isEmpty {
            args.command = token
        } else {
            args.positionals.append(token)
        }
        index += 1
    }
    return args
}

// MARK: - Output helpers

func emit(_ text: String = "") {
    print(text)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(("\(toolName): " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func usage() -> String {
    """
    \(toolName) \(toolVersion) — 一键开启 macOS HiDPI（悦高清）

    用法:
      \(toolName) list                        查看显示器、当前模式与可用 HiDPI 档位
      \(toolName) status                      查看覆盖文件与全局开关状态
      \(toolName) generate [选项]             只生成 plist，不写入系统（可 --out 指定目录）
      \(toolName) enable [选项]               安装覆盖文件并开启 DisplayResolutionEnabled
      \(toolName) disable [--display N | --all]  移除本工具安装的覆盖文件
      \(toolName) set <宽x高> [--display N]   立即切换到某个 HiDPI 逻辑分辨率
      \(toolName) doctor                      环境自检
      \(toolName) selftest                    运行内置不变量检查（不需要 Xcode）

    选项:
      --display <id|序号>   只处理某个显示器（序号取自 list 输出第一列）
      --res  <1600x900,...> 指定逻辑分辨率，逗号分隔（默认按面板自动推算）
      --out  <目录>          generate 的输出目录
      --root <目录>          演练用：把 /Library 换成指定根目录（不需要 sudo）
      --json                 机器可读输出
      --restart-windowserver enable 后立刻重启 WindowServer（会关闭所有 App）
      --diff                 只打印将要写入的内容

    示例:
      \(toolName) enable                          # 全部显示器
      \(toolName) enable --display 0 --res 1600x900,1440x810
      \(toolName) set 1600x900
      \(toolName) disable --all
    """
}

// MARK: - Entry point

let args = parseArguments(Array(CommandLine.arguments.dropFirst()))

if args.flag("--help") || args.flag("-h") || args.command == "help" {
    emit(usage())
    exit(0)
}
if args.flag("--version") || args.command == "version" {
    emit("\(toolName) \(toolVersion)")
    exit(0)
}
if args.command.isEmpty {
    emit(usage())
    exit(2)
}

let exitCode: Int32
switch args.command {
case "list":     exitCode = CommandList.run(args)
case "status":   exitCode = CommandStatus.run(args)
case "generate": exitCode = CommandGenerate.run(args)
case "enable":   exitCode = CommandEnable.run(args)
case "disable":  exitCode = CommandDisable.run(args)
case "set":      exitCode = CommandSet.run(args)
case "doctor":   exitCode = CommandDoctor.run(args)
case "selftest": exitCode = CommandSelfTest.run(args)
default:
    FileHandle.standardError.write(("\(toolName): 未知命令 “\(args.command)”\n\n").data(using: .utf8)!)
    emit(usage())
    exitCode = 2
}
exit(exitCode)
