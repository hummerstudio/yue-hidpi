import CoreGraphics
import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// A resolution pair. Kept as a struct (not a tuple) so it can be encoded to JSON.
public struct Size2D: Codable, Hashable, Comparable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static func < (lhs: Size2D, rhs: Size2D) -> Bool {
        lhs.width * lhs.height < rhs.width * rhs.height
    }

    public var label: String { "\(width) × \(height)" }
    public var area: Int { width * height }

    /// Parses "1920x1080", "1920X1080", "1920*1080" or "1920 1080".
    public init?(string: String) {
        let separators = CharacterSet(charactersIn: "xX×*, ")
        let parts = string.components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 2,
              let w = Int(parts[0]), let h = Int(parts[1]),
              (640...16384).contains(w), (480...16384).contains(h) else { return nil }
        self.init(width: w, height: h)
    }
}

public struct ModeInfo: Codable, Hashable {
    public let width: Int          // logical points
    public let height: Int
    public let pixelWidth: Int     // backing pixels
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public var isCurrent: Bool

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double, isHiDPI: Bool, isCurrent: Bool = false) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
        self.isCurrent = isCurrent
    }

    public init(cgMode: CGDisplayMode, isCurrent: Bool) {
        self.width = cgMode.width
        self.height = cgMode.height
        self.pixelWidth = cgMode.pixelWidth
        self.pixelHeight = cgMode.pixelHeight
        self.refreshRate = cgMode.refreshRate
        // macOS renders a HiDPI mode with more backing pixels than points.
        self.isHiDPI = cgMode.pixelWidth > cgMode.width || cgMode.pixelHeight > cgMode.height
        self.isCurrent = isCurrent
    }

    public var size: Size2D { Size2D(width: width, height: height) }

    public var label: String {
        let base = "\(width) × \(height)"
        return isHiDPI ? base + " HiDPI" : base
    }
}

public struct DisplayInfo: Codable {
    public let id: UInt32
    public let name: String
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32
    public let isBuiltin: Bool
    public let isMain: Bool
    public let panelPixelWidth: Int
    public let panelPixelHeight: Int
    public var modes: [ModeInfo]
    public var current: ModeInfo?

    public init(id: UInt32, name: String, vendorID: UInt32, productID: UInt32,
                serialNumber: UInt32, isBuiltin: Bool, isMain: Bool,
                panelPixelWidth: Int, panelPixelHeight: Int,
                modes: [ModeInfo], current: ModeInfo?) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.panelPixelWidth = panelPixelWidth
        self.panelPixelHeight = panelPixelHeight
        self.modes = modes
        self.current = current
    }

    public var panelSize: Size2D {
        Size2D(width: panelPixelWidth, height: panelPixelHeight)
    }

    /// Logical sizes that already have a HiDPI mode available right now.
    public var availableHiDPISizes: [Size2D] {
        var seen = Set<Size2D>()
        var out: [Size2D] = []
        for m in modes where m.isHiDPI {
            if seen.insert(m.size).inserted { out.append(m.size) }
        }
        return out.sorted(by: >)
    }

    public var isCurrentlyHiDPI: Bool {
        current?.isHiDPI ?? false
    }

    public var vendorHex: String { String(format: "%x", vendorID) }
    public var productHex: String { String(format: "%x", productID) }
}

public enum DisplayEnumerator {

    /// Every online display, main screen first, then built-in.
    public static func all() -> [DisplayInfo] {
        let names = screenNames()
        var ids = onlineDisplayIDs()
        var result: [DisplayInfo] = []
        for id in ids {
            result.append(display(id: id, name: names[id] ?? fallbackName(id)))
        }
        let mainID = CGMainDisplayID()
        result.sort { lhs, rhs in
            if lhs.id == mainID { return true }
            if rhs.id == mainID { return false }
            if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin }
            return lhs.id < rhs.id
        }
        ids.removeAll()
        return result
    }

    public static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public static func display(id: CGDirectDisplayID, name: String) -> DisplayInfo {
        let currentRef = CGDisplayCopyDisplayMode(id)
        let currentInfo = currentRef.map { ModeInfo(cgMode: $0, isCurrent: true) }

        var infos: [ModeInfo] = []
        var seen = Set<String>()
        for ref in copyAllModes(id) {
            var info = ModeInfo(cgMode: ref, isCurrent: false)
            // kCGDisplayShowDuplicateLowResolutionModes reports every mode twice.
            let key = "\(info.width)x\(info.height)@\(info.pixelWidth)x\(info.pixelHeight)#\(Int(info.refreshRate.rounded()))"
            guard seen.insert(key).inserted else { continue }
            if info.width == currentInfo?.width, info.height == currentInfo?.height,
               info.pixelWidth == currentInfo?.pixelWidth, info.pixelHeight == currentInfo?.pixelHeight {
                info.isCurrent = true
            }
            infos.append(info)
        }
        if let cur = currentInfo, !infos.contains(where: { $0.isCurrent }) {
            infos.insert(cur, at: 0)
        }

        // The panel's real pixel grid is the biggest *1x* mode. HiDPI modes can
        // be oversampled (a 2880×1800 panel also offers 3360×2100 for
        // "1680×1050 HiDPI"), so they must not define the panel size.
        let nativeModes = infos.filter { !$0.isHiDPI }
        let panelPool = nativeModes.isEmpty ? infos : nativeModes
        let panel = panelPool.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }

        return DisplayInfo(
            id: id,
            name: name,
            vendorID: CGDisplayVendorNumber(id),
            productID: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isMain: id == CGMainDisplayID(),
            panelPixelWidth: panel?.pixelWidth ?? 0,
            panelPixelHeight: panel?.pixelHeight ?? 0,
            modes: infos.sorted { lhs, rhs in
                if lhs.size == rhs.size { return lhs.refreshRate > rhs.refreshRate }
                return lhs.size > rhs.size
            },
            current: currentInfo
        )
    }

    /// All modes, including the duplicate low-resolution (HiDPI) variants that
    /// CG hides by default. Without this key a Retina panel reports only half
    /// of its modes and every HiDPI entry looks "missing".
    public static func copyAllModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue!] as CFDictionary
        guard let array = CGDisplayCopyAllDisplayModes(id, options) else { return [] }
        let count = CFArrayGetCount(array)
        var out: [CGDisplayMode] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { continue }
            out.append(unsafeBitCast(raw, to: CGDisplayMode.self))
        }
        return out
    }

    public static func modeRef(_ id: CGDirectDisplayID, matching size: Size2D, hiDPI: Bool) -> CGDisplayMode? {
        for ref in copyAllModes(id) {
            let info = ModeInfo(cgMode: ref, isCurrent: false)
            if info.size == size && info.isHiDPI == hiDPI { return ref }
        }
        return nil
    }

    private static func fallbackName(_ id: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)"
    }

    private static func screenNames() -> [UInt32: String] {
        #if canImport(AppKit)
        var map: [UInt32: String] = [:]
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
            let name = screen.localizedName
            if !name.isEmpty { map[number.uint32Value] = name }
        }
        return map
        #else
        return [:]
        #endif
    }
}
