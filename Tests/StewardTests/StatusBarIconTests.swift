import AppKit
import XCTest
@testable import Steward

final class StatusBarIconTests: XCTestCase {
    func testConfiguredImageAppliesTemplateAndSize() {
        let image = NSImage(size: NSSize(width: 64, height: 64))

        let configured = StatusBarIcon.configuredImage(image)

        XCTAssertTrue(configured.isTemplate)
        XCTAssertEqual(configured.size, StatusBarIcon.pointSize)
    }

    func testSymbolImageReturnsTemplateSizedImage() {
        let image = StatusBarIcon.symbolImage(named: "pencil.and.outline")

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, StatusBarIcon.pointSize)
    }

    func testReadyImageLoadsFromAssetsDirectoryInCurrentWorkingDirectory() throws {
        let fileManager = FileManager.default
        let originalDirectory = fileManager.currentDirectoryPath
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("StatusBarIconTests-\(UUID().uuidString)", isDirectory: true)
        let assetsDirectory = tempDirectory.appendingPathComponent("Assets", isDirectory: true)

        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try Self.samplePNGData.write(to: assetsDirectory.appendingPathComponent("status-icon.png"))

        XCTAssertTrue(fileManager.changeCurrentDirectoryPath(tempDirectory.path))
        defer {
            _ = fileManager.changeCurrentDirectoryPath(originalDirectory)
            try? fileManager.removeItem(at: tempDirectory)
        }

        let image = StatusBarIcon.readyImage(in: .main)

        XCTAssertNotNil(image)
        XCTAssertTrue(image?.isTemplate == true)
        XCTAssertEqual(image?.size, StatusBarIcon.pointSize)
    }

    private static let samplePNGData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+G1cAAAAASUVORK5CYII="
    )!
}
