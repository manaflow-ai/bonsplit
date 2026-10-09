import XCTest
@testable import Bonsplit

/// SwiftPM's generated `Bundle.module` traps with "unable to find bundle named
/// Bonsplit_Bonsplit" when the resource bundle is unreachable on first use,
/// for example after the running app was moved, trashed or its volume was
/// unmounted. Bonsplit's localized strings must fall back to their English
/// defaults instead.
final class BonsplitResourceBundleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BonsplitResourceBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    func testMissingResourceBundleResolvesToNil() throws {
        let emptyDirectory = try makeTemporaryDirectory()
        let removedDirectory = emptyDirectory.appendingPathComponent("Moved.app/Contents/Resources", isDirectory: true)

        let bundle = BonsplitResourceBundle.resolve(candidateDirectories: [nil, emptyDirectory, removedDirectory])

        XCTAssertNil(bundle)
    }

    func testMissingResourceBundleFallsBackToDefaultValue() {
        let value = BonsplitResourceBundle.localizedString(
            forKey: "tab.close.accessibilityLabel",
            defaultValue: "Close Tab",
            in: nil
        )

        XCTAssertEqual(value, "Close Tab")
    }

    func testResolvesResourceBundleFromFirstCandidateThatContainsIt() throws {
        let emptyDirectory = try makeTemporaryDirectory()
        let resourcesDirectory = try makeTemporaryDirectory()
        let bundleURL = resourcesDirectory
            .appendingPathComponent(BonsplitResourceBundle.bundleName + ".bundle", isDirectory: true)
        let stringsDirectory = bundleURL.appendingPathComponent("Contents/Resources/en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: stringsDirectory, withIntermediateDirectories: true)
        try Data("\"tab.close.accessibilityLabel\" = \"Close This Tab\";\n".utf8)
            .write(to: stringsDirectory.appendingPathComponent("Localizable.strings"))

        let bundle = try XCTUnwrap(
            BonsplitResourceBundle.resolve(candidateDirectories: [emptyDirectory, resourcesDirectory])
        )

        XCTAssertEqual(bundle.bundleURL.standardizedFileURL, bundleURL.standardizedFileURL)
        XCTAssertEqual(
            BonsplitResourceBundle.localizedString(
                forKey: "tab.close.accessibilityLabel",
                defaultValue: "Close Tab",
                in: bundle
            ),
            "Close This Tab"
        )
    }

    func testPackageResourceBundleIsReachableInTestBuilds() {
        XCTAssertNotNil(BonsplitResourceBundle.bundle)
    }
}
