import Foundation

public struct CommandResult {
    public let status: Int32
    public let output: String

    public var succeeded: Bool { status == 0 }
}

public enum Shell {
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

/// The global switch that makes WindowServer honour display overrides.
public enum WindowServerFlag {
    public static let domain = "/Library/Preferences/com.apple.windowserver"
    public static let key = "DisplayResolutionEnabled"

    /// nil when the key is absent (Apple's default is off).
    public static func read() -> Bool? {
        let result = Shell.run("/usr/bin/defaults", ["read", domain, key])
        guard result.succeeded else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    public static func write(_ enabled: Bool) throws {
        let result = Shell.run("/usr/bin/defaults",
                               ["write", domain, key, "-bool", enabled ? "true" : "false"])
        guard result.succeeded else {
            throw YueError.permission("写入 \(domain) \(key) 失败：\(result.output)")
        }
    }
}

public enum Privilege {
    public static var isRoot: Bool { geteuid() == 0 }

    /// Re-runs the current command through sudo, inheriting the terminal so the
    /// password prompt works normally. Never returns.
    public static func elevate(arguments: [String]) throws -> Never {
        guard let selfPath = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            throw YueError.io("无法定位自身可执行文件路径")
        }
        var args = [selfPath]
        args.append(contentsOf: arguments)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = args
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
    }
}

public enum WindowServer {
    /// Restarts WindowServer, which applies overrides immediately but logs the
    /// user out (every app closes). Opt-in only, never automatic.
    public static func restart() throws {
        let result = Shell.run("/usr/bin/killall", ["-HUP", "WindowServer"])
        // killall reports "No matching processes" nicely enough; a non-zero
        // status here means SessionUI refused, so surface it.
        if !result.succeeded && !result.output.contains("No matching processes") {
            throw YueError.io("重启 WindowServer 失败：\(result.output)")
        }
    }
}
