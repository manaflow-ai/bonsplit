import Foundation
import SwiftUI

extension SplitViewController {
    /// The longest a dropped tab stays hidden: a session whose end AppKit
    /// never reports shows the tab after this.
    static let tabSettleLimit: TimeInterval = 0.5

    /// `tabId` was dropped and its drag image slides into its slot: the tab
    /// draws nothing there until the session ends or ``tabSettleLimit`` passes.
    func beginTabSettle(_ tabId: UUID) {
        tabSettleGeneration += 1
        let generation = tabSettleGeneration
        withTransaction(Transaction(animation: nil)) {
            settlingTabId = tabId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tabSettleLimit) { [weak self] in
            guard let self, self.tabSettleGeneration == generation else { return }
            self.endTabSettle()
        }
    }

    /// The dropped tab shows in its slot, in place of the landed drag image.
    func endTabSettle() {
        guard settlingTabId != nil else { return }
        withTransaction(Transaction(animation: nil)) {
            settlingTabId = nil
        }
    }
}
