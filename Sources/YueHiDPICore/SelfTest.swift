import Foundation

/// Built-in invariant checks. They live in the library (not only in the test
/// target) so that `yue-hidpi selftest` can verify the binary on any machine —
/// including ones with Command Line Tools only, where XCTest is unavailable.
public struct SelfTestResult: Codable {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String = "") {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public enum SelfTest {

    public static func run() -> [SelfTestResult] {
        var results: [SelfTestResult] = []
        func expect(_ name: String, _ condition: Bool, _ detail: String = "") {
            results.append(SelfTestResult(name: name, passed: condition, detail: detail))
        }

        // 1. Byte layout must match Apple's own overrides.
        let entry = OverrideEntryFormat.hiDPI(logical: Size2D(width: 1920, height: 1080))
        let hex = entry.map { String(format: "%02x", $0) }.joined()
        expect("HiDPI 条目字节布局", hex == "00000f00000008700000000100200000", hex)

        // 2. Decoding Apple's sample entry.
        let appleEntry = Data([0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x06, 0x40,
                               0x00, 0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x00])
        expect("解码 Apple 样本条目",
               OverrideEntryFormat.decodeHiDPI(appleEntry) == Size2D(width: 1280, height: 800))

        // 3. A plain 12-byte mode entry must not be read as HiDPI.
        let plain = Data([0x00, 0x00, 0x06, 0x90, 0x00, 0x00, 0x04, 0x1a, 0x00, 0x00, 0x00, 0x01])
        expect("拒绝非 HiDPI 条目", OverrideEntryFormat.decodeHiDPI(plain) == nil)

        // 4. On-disk naming.
        let document = try? OverrideDocument(vendorID: 1552, productID: 0xa03e,
                                             logicalSizes: [Size2D(width: 1440, height: 900)])
        expect("覆盖文件命名与 Apple 一致",
               document?.relativePath == "DisplayVendorID-610/DisplayProductID-a03e",
               document?.relativePath ?? "nil")

        // 5. Dedupe + descending order.
        let messy = try? OverrideDocument(vendorID: 1, productID: 2, logicalSizes: [
            Size2D(width: 1280, height: 800),
            Size2D(width: 1440, height: 900),
            Size2D(width: 1280, height: 800),
        ])
        expect("档位去重并按尺寸降序",
               messy?.logicalSizes == [Size2D(width: 1440, height: 900), Size2D(width: 1280, height: 800)],
               "\(messy?.logicalSizes.count ?? -1) 项")

        // 6. Size parsing.
        expect("解析 1920x1080", Size2D(string: "1920x1080") == Size2D(width: 1920, height: 1080))
        expect("拒绝非法尺寸", Size2D(string: "1080p") == nil)

        // 7. Ladder for a 2880×1800 panel.
        let laptop = Ladder.defaultLogicalSizes(panelWidth: 2880, panelHeight: 1800)
        expect("2880×1800 面板档位首项为 1440×900",
               laptop.first == Size2D(width: 1440, height: 900),
               laptop.map(\.label).joined(separator: " · "))
        expect("2880×1800 面板不生成超采样档位",
               laptop.allSatisfy { $0.width * 2 <= 2880 && $0.height * 2 <= 1800 },
               laptop.map(\.label).joined(separator: " · "))

        // 8. Ladder for a 4K panel keeps 16:9.
        let monitor = Ladder.defaultLogicalSizes(panelWidth: 3840, panelHeight: 2160)
        expect("3840×2160 面板首项为 1920×1080",
               monitor.first == Size2D(width: 1920, height: 1080),
               monitor.map(\.label).joined(separator: " · "))
        expect("4K 面板不混入 16:10 档位",
               !monitor.contains(Size2D(width: 1440, height: 900)))

        // 9. Oversampling warning.
        let warnings = Ladder.warnings(for: [Size2D(width: 2560, height: 1440)],
                                       panelWidth: 3840, panelHeight: 2160)
        expect("超采样档位给出告警", warnings.count == 1, warnings.first ?? "")

        // 10. Identical monitors share one override file.
        let twinA = makeDisplay(id: 1, vendor: 1552, product: 0x9ccd, panel: Size2D(width: 3840, height: 2160))
        let twinB = makeDisplay(id: 2, vendor: 1552, product: 0x9ccd, panel: Size2D(width: 3840, height: 2160))
        let twinPlan = OverridePlanner.plan(displays: [twinA, twinB], paths: Paths(root: NSTemporaryDirectory()), resolutions: nil)
        expect("同型号显示器共用一个覆盖文件",
               twinPlan.groups.count == 1 && twinPlan.installTargets().count == 1)

        // 11. Install → read back → remove, inside a throw-away root.
        let tempRoot = NSTemporaryDirectory() + "yue-hidpi-selftest-\(UUID().uuidString)"
        let paths = Paths(root: tempRoot)
        defer { try? FileManager.default.removeItem(atPath: tempRoot) }
        do {
            let target = InstallTarget(displayID: 7, document: try OverrideDocument(
                vendorID: 1552, productID: 0xa03e,
                logicalSizes: [Size2D(width: 1440, height: 900), Size2D(width: 1280, height: 800)]))
            let installed = try Installer.install(targets: [target], paths: paths)
            let readBack = Installer.installedSizes(plistPath: installed[0].path)
            expect("安装后能读回声明的档位",
                   readBack == [Size2D(width: 1440, height: 900), Size2D(width: 1280, height: 800)],
                   readBack?.map(\.label).sorted().joined(separator: " · ") ?? "nil")
            expect("安装后写入清单",
                   Installer.loadManifest(paths: paths).records.count == 1)

            _ = try Installer.install(targets: [target], paths: paths)
            expect("重复安装不产生重复清单项",
                   Installer.loadManifest(paths: paths).records.count == 1)

            let removed = try Installer.remove(displayIDs: [], paths: paths)
            expect("移除后文件与清单都清空",
                   removed.count == 1
                    && !FileManager.default.fileExists(atPath: installed[0].path)
                    && Installer.loadManifest(paths: paths).records.isEmpty)
        } catch {
            expect("安装/移除往返", false, error.localizedDescription)
        }

        // 12. A pre-existing foreign override is backed up and restored.
        let backupRoot = NSTemporaryDirectory() + "yue-hidpi-selftest-backup-\(UUID().uuidString)"
        let backupPaths = Paths(root: backupRoot)
        defer { try? FileManager.default.removeItem(atPath: backupRoot) }
        do {
            let document = try OverrideDocument(vendorID: 42, productID: 43,
                                                logicalSizes: [Size2D(width: 1280, height: 800)])
            let destination = backupPaths.absolute(document.relativePath)
            try FileManager.default.createDirectory(atPath: (destination as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            let foreign = Data("foreign".utf8)
            try foreign.write(to: URL(fileURLWithPath: destination))

            _ = try Installer.install(targets: [InstallTarget(displayID: 9, document: document)], paths: backupPaths)
            let afterInstall = try Data(contentsOf: URL(fileURLWithPath: destination))
            let removed = try Installer.remove(displayIDs: [], paths: backupPaths)
            let afterRemove = try Data(contentsOf: URL(fileURLWithPath: destination))
            expect("外来覆盖文件被备份并在移除时还原",
                   afterInstall != foreign && removed.first?.restoredBackup == true && afterRemove == foreign)
        } catch {
            expect("外来覆盖文件备份/还原", false, error.localizedDescription)
        }

        return results
    }

    public static func makeDisplay(id: UInt32, vendor: UInt32, product: UInt32, panel: Size2D) -> DisplayInfo {
        DisplayInfo(id: id, name: "Self Test Display", vendorID: vendor, productID: product,
                    serialNumber: 0, isBuiltin: false, isMain: true,
                    panelPixelWidth: panel.width, panelPixelHeight: panel.height,
                    modes: [], current: nil)
    }
}
