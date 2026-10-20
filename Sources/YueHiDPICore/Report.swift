import Foundation

/// Terminal rendering. Deliberately dependency-free: the tool ships as one
/// binary and must work over SSH, in tmux and inside CI logs.
public enum Ansi {
    public static let enabled: Bool = {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(STDOUT_FILENO) == 1
    }()

    public static func bold(_ text: String) -> String { wrap(text, "1") }
    public static func dim(_ text: String) -> String { wrap(text, "2") }
    public static func green(_ text: String) -> String { wrap(text, "32") }
    public static func yellow(_ text: String) -> String { wrap(text, "33") }
    public static func red(_ text: String) -> String { wrap(text, "31") }
    public static func cyan(_ text: String) -> String { wrap(text, "36") }

    private static func wrap(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}

public enum Text {
    /// Width in terminal cells; CJK characters occupy two.
    public static func width(_ text: String) -> Int {
        var total = 0
        for scalar in text.unicodeScalars {
            if isWide(scalar) { total += 2 } else if scalar.value >= 0x0300 && scalar.value <= 0x036F { }
            else { total += 1 }
        }
        return total
    }

    public static func pad(_ text: String, _ target: Int) -> String {
        let delta = target - width(text)
        return delta > 0 ? text + String(repeating: " ", count: delta) : text
    }

    public static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
             0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF,
             0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

public struct Table {
    public let headers: [String]
    public private(set) var rows: [[String]] = []

    public init(headers: [String]) {
        self.headers = headers
    }

    public mutating func add(_ row: [String]) {
        rows.append(row)
    }

    public func render(headerColor: (String) -> String = { $0 }) -> String {
        var widths = headers.map { Text.width($0) }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], Text.width(cell))
            }
        }
        func line(_ cells: [String], bold: Bool) -> String {
            var parts: [String] = []
            for (index, cell) in cells.enumerated() {
                let padded = Text.pad(cell, widths[index])
                parts.append(bold ? headerColor(padded) : padded)
            }
            return "  " + parts.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }
        var lines = [line(headers, bold: true)]
        lines.append(contentsOf: rows.map { line($0, bold: false) })
        return lines.joined(separator: "\n")
    }
}

public enum Json {
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
