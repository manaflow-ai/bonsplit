import Foundation
import Observation
import Testing
@testable import Bonsplit

@Suite @MainActor
struct TabIconAnimationTests {
    private func animation(id: String = "test", loops: Bool = true) -> TabIconAnimation {
        TabIconAnimation(id: id, frames: [Data([1]), Data([2])], durations: [0.1, 0.2], loops: loops)
    }

    @Test func publicValueEqualityIncludesPlaybackDefinition() {
        let original = animation()
        #expect(original == animation())
        #expect(original != animation(id: "other"))
        #expect(original != animation(loops: false))
        #expect(original != TabIconAnimation(id: original.id, frames: original.frames, durations: [1, 2], loops: true))
        #expect(original != TabIconAnimation(id: original.id, frames: [Data([3])], durations: original.durations, loops: true))
        #expect(original != TabIconAnimation(id: original.id, frames: original.frames, durations: original.durations, loops: true, staticFrameIndex: 1))
        let id = TabID()
        #expect(Tab(id: id, title: "A").iconAnimation == nil)
        #expect(Tab(id: id, title: "A") != Tab(id: id, title: "A", iconAnimation: original))
    }

    @Test func createUpdateKeepClearAndSnapshot() throws {
        let controller = BonsplitController()
        let id = try #require(controller.createTab(title: "A", iconAnimation: animation()))
        #expect(controller.tab(id)?.iconAnimation == animation())
        controller.updateTab(id, title: "B")
        #expect(controller.tab(id)?.iconAnimation == animation())
        controller.updateTab(id, iconAnimation: .some(animation(id: "new")))
        #expect(controller.tab(id)?.iconAnimation == animation(id: "new"))
        controller.updateTab(id, iconAnimation: .some(nil))
        #expect(controller.tab(id)?.iconAnimation == nil)
    }

    @Test func identicalUpdateDoesNotInvalidateAnimationEvenWhenTitleChanges() async throws {
        let controller = BonsplitController()
        let id = try #require(controller.createTab(title: "A", iconAnimation: animation()))
        let paneID = try #require(controller.focusedPaneId)
        let pane = try #require(controller.internalController.paneState(for: paneID))
        let item = try #require(pane.tabs.first { $0.id == id.id })
        await confirmation(expectedCount: 0) { invalidated in
            withObservationTracking { _ = item.iconAnimation } onChange: { invalidated() }
            controller.updateTab(id, iconAnimation: .some(animation()))
            controller.updateTab(id, title: "B", iconAnimation: .some(animation()))
        }
        await confirmation { invalidated in
            withObservationTracking { _ = item.iconAnimation } onChange: { invalidated() }
            controller.updateTab(id, iconAnimation: .some(animation(id: "new")))
        }
    }

    @Test func animationUpdateDoesNotInvalidatePaneOrSibling() async throws {
        let controller = BonsplitController()
        let first = try #require(controller.createTab(title: "A"))
        let second = try #require(controller.createTab(title: "B"))
        let paneID = try #require(controller.focusedPaneId)
        let pane = try #require(controller.internalController.paneState(for: paneID))
        let sibling = try #require(pane.tabs.first { $0.id == second.id })
        await confirmation(expectedCount: 0) { invalidated in
            withObservationTracking {
                _ = pane.tabs
                _ = sibling.iconAnimation
            } onChange: { invalidated() }
            controller.updateTab(first, iconAnimation: .some(animation()))
        }
    }

    @Test func internalCodingRoundTripsAnimationAndAcceptsOldPayloads() throws {
        let item = TabItem(title: "A", iconAnimation: animation())
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(TabItem.self, from: encoded)
        #expect(Tab(from: decoded).iconAnimation == animation())
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"A\"}".utf8)
        #expect(try JSONDecoder().decode(TabItem.self, from: legacy).iconAnimation == nil)
    }

    @Test func splitAndAutoLayoutPreserveAnimationSnapshots() throws {
        for mode in 0..<4 {
            let controller = BonsplitController()
            let tab = Tab(title: "A", iconAnimation: animation())
            let paneID: PaneID?
            switch mode {
            case 0: paneID = controller.splitRoot(orientation: .horizontal, withTab: tab)
            case 1: paneID = controller.splitPane(orientation: .horizontal, withTab: tab)
            case 2: paneID = controller.splitPane(orientation: .horizontal, withTab: tab, insertFirst: true)
            default: paneID = controller.addPaneWithAutoLayout(withTab: tab)
            }
            _ = try #require(paneID)
            #expect(controller.tab(tab.id)?.iconAnimation == animation())
        }
    }
}
