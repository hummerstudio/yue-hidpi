import Foundation

/// Suggests HiDPI ("looks like") sizes for a panel.
///
/// Rules:
///  * never exceed the panel's native pixel grid, i.e. logical ≤ panel / 2 —
///    going above it means the GPU renders more pixels than the panel has and
///    downscales, which costs sharpness and GPU time;
///  * keep the panel's aspect ratio (a 16:10 laptop should not get 16:9 modes);
///  * prefer round, human-recognisable sizes.
public enum Ladder {
    /// Common logical resolutions. Any entry is only kept when it fits the
    /// panel and matches its aspect ratio.
    public static let knownSizes: [Size2D] = [
        // 16:10
        Size2D(width: 1680, height: 1050), Size2D(width: 1440, height: 900),
        Size2D(width: 1280, height: 800), Size2D(width: 1152, height: 720),
        Size2D(width: 1024, height: 640), Size2D(width: 900, height: 563),
        // 16:9
        Size2D(width: 3840, height: 2160), Size2D(width: 3200, height: 1800),
        Size2D(width: 2560, height: 1440), Size2D(width: 2048, height: 1152),
        Size2D(width: 1920, height: 1080), Size2D(width: 1792, height: 1008),
        Size2D(width: 1680, height: 945), Size2D(width: 1600, height: 900),
        Size2D(width: 1440, height: 810), Size2D(width: 1366, height: 768),
        Size2D(width: 1280, height: 720), Size2D(width: 1152, height: 648),
        Size2D(width: 1024, height: 576),
        // 21:9 / ultrawide
        Size2D(width: 3440, height: 1440), Size2D(width: 2560, height: 1080),
        Size2D(width: 1920, height: 800),
        // 3:2 (Surface-like panels)
        Size2D(width: 2160, height: 1440), Size2D(width: 1920, height: 1280),
        Size2D(width: 1504, height: 1000),
    ]

    public static func defaultLogicalSizes(panelWidth: Int, panelHeight: Int, limit: Int = 6) -> [Size2D] {
        guard panelWidth >= 640, panelHeight >= 480 else { return [] }
        let ratio = Double(panelWidth) / Double(panelHeight)
        let maxLogicalWidth = panelWidth / 2
        let maxLogicalHeight = panelHeight / 2

        var sizes: [Size2D] = [Size2D(width: maxLogicalWidth, height: maxLogicalHeight)]
        for candidate in knownSizes.sorted(by: >) {
            guard candidate.width <= maxLogicalWidth, candidate.height <= maxLogicalHeight else { continue }
            guard matchesAspect(candidate, ratio: ratio) else { continue }
            sizes.append(candidate)
        }

        var seen = Set<Size2D>()
        let unique = sizes.filter { seen.insert($0).inserted }
        return Array(unique.sorted(by: >).prefix(max(1, limit)))
    }

    public static func matchesAspect(_ size: Size2D, ratio: Double, tolerance: Double = 0.012) -> Bool {
        guard size.height > 0 else { return false }
        let value = Double(size.width) / Double(size.height)
        return abs(value - ratio) / ratio <= tolerance
    }

    /// Validates user supplied sizes against the panel, returning warnings.
    public static func warnings(for sizes: [Size2D], panelWidth: Int, panelHeight: Int) -> [String] {
        var out: [String] = []
        let ratio = panelHeight > 0 ? Double(panelWidth) / Double(panelHeight) : 0
        for size in sizes {
            if size.width * 2 > panelWidth || size.height * 2 > panelHeight {
                out.append("\(size.label)：像素 \(size.width * 2)×\(size.height * 2) 超出面板 \(panelWidth)×\(panelHeight)，将由 GPU 超采样缩放，清晰度与性能会下降")
            }
            if ratio > 0, !matchesAspect(size, ratio: ratio) {
                out.append("\(size.label)：宽高比与面板不同，可能出现黑边或拉伸")
            }
        }
        return out
    }
}
