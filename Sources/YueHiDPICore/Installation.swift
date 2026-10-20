import Foundation

/// Filesystem layout. `root` lets the whole tool run against a throw-away
/// directory in tests (`YUE_HIDPI_ROOT=/tmp/x`) instead of the live system.
public struct Paths {
    public let root: String

    public init(root: String = "/") {
        var value = root
        if value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        self.root = value == "/" ? "" : value
    }

    public static var live: Paths { Paths(root: "/") }

    public var overridesDirectory: String {
        root + "/Library/Displays/Contents/Resources/Overrides"
    }

    public var supportDirectory: String {
        root + "/Library/Application Support/yue-hidpi"
    }

    public var manifestFile: String {
        supportDirectory + "/manifest.json"
    }

    public func absolute(_ relativePath: String) -> String {
        overridesDirectory + "/" + relativePath
    }
}

public struct InstalledRecord: Codable {
    public var relativePath: String
    public var displayID: UInt32
    public var vendorID: UInt32
    public var productID: UInt32
    public var sizes: [Size2D]
    public var backupRelativePath: String?
    public var createdAt: Date
}

public struct Manifest: Codable {
    public var version: Int
    public var records: [InstalledRecord]
    public var displayResolutionEnabledTouched: Bool
    public var previousDisplayResolutionEnabled: Bool?

    public init(version: Int = 1,
                records: [InstalledRecord] = [],
                displayResolutionEnabledTouched: Bool = false,
                previousDisplayResolutionEnabled: Bool? = nil) {
        self.version = version
        self.records = records
        self.displayResolutionEnabledTouched = displayResolutionEnabledTouched
        self.previousDisplayResolutionEnabled = previousDisplayResolutionEnabled
    }

    public func record(forDisplay id: UInt32) -> InstalledRecord? {
        records.first { $0.displayID == id }
    }
}

public struct InstallTarget {
    public let displayID: UInt32
    public let document: OverrideDocument

    public init(displayID: UInt32, document: OverrideDocument) {
        self.displayID = displayID
        self.document = document
    }
}

public struct InstallResult: Codable {
    public let displayID: UInt32
    public let path: String
    public let sizes: [Size2D]
    public let replacedPreviousFile: Bool
}

public struct RemoveResult: Codable {
    public let displayID: UInt32
    public let path: String
    public let restoredBackup: Bool
}

public enum Installer {
    public static let backupSuffix = ".yue-hidpi.bak"

    // MARK: - Manifest

    public static func loadManifest(paths: Paths) -> Manifest {
        guard let data = FileManager.default.contents(atPath: paths.manifestFile) else {
            return Manifest()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Manifest.self, from: data)) ?? Manifest()
    }

    public static func saveManifest(_ manifest: Manifest, paths: Paths) throws {
        try ensureDirectory(paths.supportDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: paths.manifestFile), options: .atomic)
        try applySystemOwnership(paths.manifestFile)
    }

    // MARK: - Install / remove

    public static func install(targets: [InstallTarget], paths: Paths) throws -> [InstallResult] {
        try ensureDirectory(paths.overridesDirectory)
        var manifest = loadManifest(paths: paths)
        var results: [InstallResult] = []

        for target in targets {
            let document = target.document
            let relative = document.relativePath
            let destination = paths.absolute(relative)
            try ensureDirectory((destination as NSString).deletingLastPathComponent)

            var backupRelative: String?
            var replaced = false
            if FileManager.default.fileExists(atPath: destination) {
                replaced = true
                // Only back up files we did not write ourselves.
                let existing = installedSizes(plistPath: destination)
                let ours = manifest.records.contains { $0.relativePath == relative }
                if existing == nil && !ours {
                    backupRelative = relative + backupSuffix
                    try? FileManager.default.removeItem(atPath: paths.absolute(backupRelative!))
                    try FileManager.default.copyItem(atPath: destination,
                                                     toPath: paths.absolute(backupRelative!))
                } else if let previous = manifest.records.first(where: { $0.relativePath == relative }) {
                    backupRelative = previous.backupRelativePath
                }
            }

            let data = try document.xmlData()
            try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
            try applySystemOwnership(destination, mode: 0o644)
            try applySystemOwnership((destination as NSString).deletingLastPathComponent, mode: 0o755)

            manifest.records.removeAll { $0.relativePath == relative }
            manifest.records.append(InstalledRecord(
                relativePath: relative,
                displayID: target.displayID,
                vendorID: document.vendorID,
                productID: document.productID,
                sizes: document.logicalSizes,
                backupRelativePath: backupRelative,
                createdAt: Date()
            ))
            results.append(InstallResult(displayID: target.displayID,
                                         path: destination,
                                         sizes: document.logicalSizes,
                                         replacedPreviousFile: replaced))
        }

        try saveManifest(manifest, paths: paths)
        return results
    }

    public static func remove(displayIDs: [UInt32], paths: Paths) throws -> [RemoveResult] {
        var manifest = loadManifest(paths: paths)
        var results: [RemoveResult] = []

        let targets = manifest.records.filter { displayIDs.isEmpty || displayIDs.contains($0.displayID) }
        for record in targets {
            let destination = paths.absolute(record.relativePath)
            var restored = false
            if FileManager.default.fileExists(atPath: destination) {
                try FileManager.default.removeItem(atPath: destination)
            }
            if let backup = record.backupRelativePath {
                let backupPath = paths.absolute(backup)
                if FileManager.default.fileExists(atPath: backupPath) {
                    try FileManager.default.moveItem(atPath: backupPath, toPath: destination)
                    try applySystemOwnership(destination, mode: 0o644)
                    restored = true
                }
            }
            pruneEmptyVendorDirectory(for: record.relativePath, paths: paths)
            results.append(RemoveResult(displayID: record.displayID,
                                        path: destination,
                                        restoredBackup: restored))
            manifest.records.removeAll { $0.relativePath == record.relativePath }
        }

        try saveManifest(manifest, paths: paths)
        return results
    }

    public static func removeAll(paths: Paths) throws -> [RemoveResult] {
        try remove(displayIDs: [], paths: paths)
    }

    // MARK: - Inspection

    /// Logical HiDPI sizes declared by an override file on disk.
    /// Returns nil when the file is missing or unreadable.
    public static func installedSizes(plistPath: String) -> Set<Size2D>? {
        guard let data = FileManager.default.contents(atPath: plistPath) else { return nil }
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any],
              let entries = dictionary["scale-resolutions"] as? [Data] else { return nil }
        var sizes = Set<Size2D>()
        for entry in entries {
            if let size = OverrideEntryFormat.decodeHiDPI(entry) { sizes.insert(size) }
            else if entry.count == 12 {
                let words = entry.bigEndianUInt32s()
                if words.count == 3, words[0] > 0, words[1] > 0 {
                    sizes.insert(Size2D(width: Int(words[0]), height: Int(words[1])))
                }
            }
        }
        return sizes
    }

    public static func overridePath(for display: DisplayInfo, paths: Paths) -> String {
        paths.absolute("DisplayVendorID-\(String(display.vendorID, radix: 16))/DisplayProductID-\(String(display.productID, radix: 16))")
    }

    public static func hasOverride(for display: DisplayInfo, paths: Paths) -> Bool {
        FileManager.default.fileExists(atPath: overridePath(for: display, paths: paths))
    }

    // MARK: - Helpers

    static func ensureDirectory(_ path: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            throw YueError.io("无法创建目录 \(path)：\(error.localizedDescription)")
        }
        try applySystemOwnership(path, mode: 0o755)
    }

    /// Overrides are read by WindowServer (root); keep root:wheel like Apple's.
    static func applySystemOwnership(_ path: String, mode: mode_t? = nil) throws {
        if geteuid() == 0 {
            chown(path, 0, 0)
        }
        if let mode = mode {
            chmod(path, mode)
        }
    }

    static func pruneEmptyVendorDirectory(for relativePath: String, paths: Paths) {
        let directory = (paths.absolute(relativePath) as NSString).deletingLastPathComponent
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        if contents.isEmpty {
            try? FileManager.default.removeItem(atPath: directory)
        }
    }
}
