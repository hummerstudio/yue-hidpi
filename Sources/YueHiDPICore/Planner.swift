import Foundation

/// One override file, possibly shared by several identical monitors
/// (the plist is keyed by vendor/product, so two identical displays get one file).
public struct OverrideGroup {
    public let displayIDs: [UInt32]
    public let document: OverrideDocument
}

public struct OverridePlan {
    public let groups: [OverrideGroup]
    public let warnings: [String]

    public init(groups: [OverrideGroup], warnings: [String]) {
        self.groups = groups
        self.warnings = warnings
    }

    public func installTargets() -> [InstallTarget] {
        groups.compactMap { group in
            guard let id = group.displayIDs.first else { return nil }
            return InstallTarget(displayID: id, document: group.document)
        }
    }

    /// What to suggest in the "now run set …" hint: the widest mode the plan
    /// adds. CLI syntax, not the pretty label, so it can be pasted back.
    public var preferredSizeLabel: String? {
        groups.flatMap { $0.document.logicalSizes }.max().map { "\($0.width)x\($0.height)" }
    }
}

public enum OverridePlanner {

    public static func plan(displays: [DisplayInfo], paths: Paths, resolutions: String?) -> OverridePlan {
        let explicit = resolutions.map(parseSizes) ?? []
        var warnings: [String] = []
        var sizesByModel: [ModelKey: [Size2D]] = [:]
        var idsByModel: [ModelKey: [UInt32]] = [:]
        var order: [ModelKey] = []

        for display in displays {
            var sizes: [Size2D]
            if !explicit.isEmpty {
                sizes = explicit
                warnings.append(contentsOf: Ladder.warnings(for: sizes,
                                                            panelWidth: display.panelPixelWidth,
                                                            panelHeight: display.panelPixelHeight)
                                    .map { "\(display.name) \($0)" })
            } else {
                sizes = Ladder.defaultLogicalSizes(panelWidth: display.panelPixelWidth,
                                                   panelHeight: display.panelPixelHeight)
                // Never silently drop sizes the user added earlier.
                if let existing = Installer.installedSizes(plistPath: Installer.overridePath(for: display, paths: paths)) {
                    sizes.append(contentsOf: existing)
                }
                if sizes.isEmpty {
                    warnings.append("\(display.name)：面板像素 \(display.panelPixelWidth)×\(display.panelPixelHeight) 过小，无法推算档位，请用 --res 指定")
                }
            }

            let key = ModelKey(vendorID: display.vendorID, productID: display.productID)
            if sizesByModel[key] == nil {
                sizesByModel[key] = []
                idsByModel[key] = []
                order.append(key)
            }
            sizesByModel[key]?.append(contentsOf: sizes)
            idsByModel[key]?.append(display.id)
        }

        var groups: [OverrideGroup] = []
        for key in order {
            guard let sizes = sizesByModel[key], !sizes.isEmpty,
                  let ids = idsByModel[key] else { continue }
            guard let document = try? OverrideDocument(vendorID: key.vendorID,
                                                        productID: key.productID,
                                                        logicalSizes: sizes) else { continue }
            groups.append(OverrideGroup(displayIDs: ids, document: document))
        }

        // Identical models configured with the same sizes should warn once each.
        var seenWarnings = Set<String>()
        let uniqueWarnings = warnings.filter { seenWarnings.insert($0).inserted }
        return OverridePlan(groups: groups, warnings: uniqueWarnings)
    }

    public static func parseSizes(_ raw: String) -> [Size2D] {
        raw.split(separator: ",").compactMap { Size2D(string: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    public struct ModelKey: Hashable {
        public let vendorID: UInt32
        public let productID: UInt32
    }
}
