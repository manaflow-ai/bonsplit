import Foundation
import XCTest
@testable import Bonsplit

final class DeferredActionOwnershipTests: XCTestCase {
    func testTabItemViewDoesNotOwnReplaceableDispatchWorkItemsInState() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/Bonsplit/Internal/Views/TabItemView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("DispatchWorkItem"),
            """
            TabItemView must delegate replaceable deferred work to a reference-owned scheduler. \
            A queued closure can capture the view's stale @State inline value and retain the \
            predecessor work item, creating an unbounded recursive release chain.
            """
        )
    }
}
