import CoreGraphics
import Foundation

/// Format of a single `scale-resolutions` entry, reverse-engineered from
/// Apple's own overrides (e.g. /System/Library/Displays/…/DisplayVendorID-610/
/// DisplayProductID-a040) and cross-checked against the community scripts:
///
///   big-endian UInt32 pixelWidth
///   big-endian UInt32 pixelHeight
///   big-endian UInt32 flags        (0x00000001 = usable mode)
///   big-endian UInt32 modeClass    (0x00200000 = HiDPI / 2x backing)
///
/// Entries are *pixel* dimensions. A logical 1440×900 HiDPI mode is stored as
/// 2880×1800 pixels + 0x00200000, and macOS then offers "1440 × 900 (HiDPI)".
public enum OverrideEntryFormat {
    public static let flagsBase: UInt32 = 0x0000_0001
    public static let modeClassHiDPI: UInt32 = 0x0020_0000
    public static let entryLengthHiDPI = 16

    public static func hiDPI(logical: Size2D) -> Data {
        var data = Data(capacity: entryLengthHiDPI)
        data.appendUInt32BE(UInt32(logical.width * 2))
        data.appendUInt32BE(UInt32(logical.height * 2))
        data.appendUInt32BE(flagsBase)
        data.appendUInt32BE(modeClassHiDPI)
        return data
    }

    /// Round-trips an entry back to a logical size, for status/verification.
    public static func decodeHiDPI(_ data: Data) -> Size2D? {
        guard data.count == entryLengthHiDPI else { return nil }
        let words = data.bigEndianUInt32s()
        guard words.count == 4, words[3] == modeClassHiDPI, words[2] != 0 else { return nil }
        guard words[0] % 2 == 0, words[1] % 2 == 0 else { return nil }
        return Size2D(width: Int(words[0] / 2), height: Int(words[1] / 2))
    }
}

extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }

    func bigEndianUInt32s() -> [UInt32] {
        let bytes = [UInt8](self)
        guard bytes.count % 4 == 0 else { return [] }
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
        }
    }
}

/// One display's override document.
public struct OverrideDocument {
    public let vendorID: UInt32
    public let productID: UInt32
    public let logicalSizes: [Size2D]

    public init(vendorID: UInt32, productID: UInt32, logicalSizes: [Size2D]) throws {
        guard !logicalSizes.isEmpty else {
            throw YueError.invalidArgument("没有可用的分辨率档位（至少需要一个 HiDPI 分辨率）")
        }
        self.vendorID = vendorID
        self.productID = productID
        self.logicalSizes = Self.deduplicated(logicalSizes)
    }

    public static func deduplicated(_ sizes: [Size2D]) -> [Size2D] {
        var seen = Set<Size2D>()
        return sizes.filter { seen.insert($0).inserted }.sorted(by: >)
    }

    public var entries: [Data] {
        logicalSizes.map { OverrideEntryFormat.hiDPI(logical: $0) }
    }

    public func plistObject() -> [String: Any] {
        [
            "DisplayProductID": Int(productID),
            "DisplayVendorID": Int(vendorID),
            "scale-resolutions": entries,
        ]
    }

    public func xmlData() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plistObject(),
                                           format: .xml,
                                           options: 0)
    }

    /// Apple's on-disk convention: lowercase hex, no zero padding, no 0x prefix.
    public var vendorDirectoryName: String { "DisplayVendorID-\(String(vendorID, radix: 16))" }
    public var fileName: String { "DisplayProductID-\(String(productID, radix: 16))" }

    public var relativePath: String { "\(vendorDirectoryName)/\(fileName)" }
}

public enum YueError: Error, LocalizedError {
    case invalidArgument(String)
    case notFound(String)
    case permission(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let text): return text
        case .notFound(let text): return text
        case .permission(let text): return text
        case .io(let text): return text
        }
    }
}
