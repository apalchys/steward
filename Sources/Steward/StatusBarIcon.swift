import AppKit

enum StatusBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    static func readyImage(in bundle: Bundle = .main) -> NSImage? {
        loadImage(named: "status-icon", in: bundle) ?? loadImage(named: "statusicon", in: bundle)
    }

    static func symbolImage(named symbolName: String) -> NSImage {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return NSImage(size: pointSize)
        }

        return configuredImage(image)
    }

    static func loadImage(named name: String, in bundle: Bundle = .main) -> NSImage? {
        let candidates = [
            bundle.url(forResource: name, withExtension: "png"),
            bundle.resourceURL?.appendingPathComponent("\(name).png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/\(name).png"),
        ]

        for url in candidates.compactMap({ $0 }) {
            guard let image = NSImage(contentsOf: url) else {
                continue
            }

            return configuredImage(image)
        }

        return nil
    }

    static func configuredImage(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        image.size = pointSize
        return image
    }
}
