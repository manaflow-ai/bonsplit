import Foundation

/// Locates Bonsplit's SwiftPM resource bundle without trapping.
///
/// SwiftPM's generated `Bundle.module` calls `fatalError` when
/// `Bonsplit_Bonsplit.bundle` is not reachable the first time it is read. A
/// running app hits that when its bundle moved, was trashed or replaced, or
/// its volume was unmounted before a tab first needed a localized string.
/// Bonsplit's strings are accessibility labels and menu titles with English
/// defaults, so a missing bundle falls back to those defaults instead.
enum BonsplitResourceBundle {
    static let bundleName = "Bonsplit_Bonsplit"

    private final class BundleFinder {}

    /// The resource bundle, or `nil` when it was unreachable on first use.
    static let bundle: Bundle? = resolve(candidateDirectories: defaultCandidateDirectories)

    /// Same search order as SwiftPM's generated accessor, plus the directory
    /// next to the bundle that contains this code, which is where
    /// `swift build` and `swift test` place package resource bundles.
    private static var defaultCandidateDirectories: [URL?] {
        var directories: [URL?] = []
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            directories.append(URL(fileURLWithPath: override))
        }
#endif
        let codeBundle = Bundle(for: BundleFinder.self)
        directories.append(Bundle.main.resourceURL)
        directories.append(codeBundle.resourceURL)
        directories.append(Bundle.main.bundleURL)
        directories.append(codeBundle.bundleURL.deletingLastPathComponent())
        return directories
    }

    static func resolve(candidateDirectories: [URL?]) -> Bundle? {
        for directory in candidateDirectories {
            guard let directory else { continue }
            let url = directory.appendingPathComponent(bundleName + ".bundle", isDirectory: true)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }

    static func localizedString(forKey key: String, defaultValue: String) -> String {
        localizedString(forKey: key, defaultValue: defaultValue, in: bundle)
    }

    static func localizedString(forKey key: String, defaultValue: String, in bundle: Bundle?) -> String {
        guard let bundle else { return defaultValue }
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
