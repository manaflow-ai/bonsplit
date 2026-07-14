import AppKit
import SwiftUI

@MainActor
protocol TabBarItemGeometryObserving: AnyObject {
    func tabBarItemGeometryDidChange()
}

/// AppKit-owned geometry for the tab strip.
///
/// Tab frames stay in the platform view hierarchy and are queried only by
/// platform consumers. They never become SwiftUI state, so measuring or
/// scrolling the strip cannot invalidate the graph that produced the frames.
@MainActor
final class TabBarItemGeometryRegistry {
    private let itemViews = NSMapTable<NSUUID, NSView>.strongToWeakObjects()
    private let observers = NSHashTable<AnyObject>.weakObjects()
    private weak var scrollView: NSScrollView?
    private var scrollBoundsObserver: NSObjectProtocol?

    deinit {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
    }

    func register(_ view: NSView, for tabId: UUID) {
        itemViews.setObject(view, forKey: tabId as NSUUID)
        invalidateObservers()
    }

    func unregister(_ view: NSView, for tabId: UUID) {
        guard itemViews.object(forKey: tabId as NSUUID) === view else { return }
        itemViews.removeObject(forKey: tabId as NSUUID)
        invalidateObservers()
    }

    func registerObserver(_ observer: TabBarItemGeometryObserving) {
        observers.add(observer)
        observer.tabBarItemGeometryDidChange()
    }

    func unregisterObserver(_ observer: TabBarItemGeometryObserving) {
        observers.remove(observer)
    }

    func attachScrollView(_ scrollView: NSScrollView?) {
        guard self.scrollView !== scrollView else { return }
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
            self.scrollBoundsObserver = nil
        }
        self.scrollView = scrollView
        guard let clipView = scrollView?.contentView else {
            invalidateObservers()
            return
        }

        // Keep the documented AppKit scroll signal outside SwiftUI so chrome
        // redraws do not publish geometry into the view graph.
        clipView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateObservers()
            }
        }
        invalidateObservers()
    }

    func frame(for tabId: UUID, in targetView: NSView) -> CGRect? {
        guard let itemView = itemViews.object(forKey: tabId as NSUUID),
              itemView.window === targetView.window,
              isVisibleInHierarchy(itemView) else {
            return nil
        }
        return itemView.convert(itemView.bounds, to: targetView)
    }

    func frames(for tabIds: [UUID], in targetView: NSView) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        frames.reserveCapacity(tabIds.count)
        for tabId in tabIds {
            if let frame = frame(for: tabId, in: targetView) {
                frames[tabId] = frame
            }
        }
        return frames
    }

    func geometryDidChange() {
        invalidateObservers()
    }

    private func invalidateObservers() {
        for case let observer as TabBarItemGeometryObserving in observers.allObjects {
            observer.tabBarItemGeometryDidChange()
        }
    }

    private func isVisibleInHierarchy(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            guard !candidate.isHidden, candidate.alphaValue > 0 else { return false }
            current = candidate.superview
        }
        return true
    }
}

struct TabItemHitRegionView: NSViewRepresentable {
    let tabId: UUID
    let geometryRegistry: TabBarItemGeometryRegistry

    func makeNSView(context: Context) -> RegionNSView {
        let view = RegionNSView()
        view.configure(tabId: tabId, geometryRegistry: geometryRegistry)
        return view
    }

    func updateNSView(_ nsView: RegionNSView, context: Context) {
        nsView.configure(tabId: tabId, geometryRegistry: geometryRegistry)
    }

    final class RegionNSView: NSView, BonsplitTabItemHitRegionProviding {
        nonisolated(unsafe) private var hitBounds: NSRect = .zero
        private var tabId: UUID?
        private weak var geometryRegistry: TabBarItemGeometryRegistry?

        override var mouseDownCanMoveWindow: Bool { false }

        deinit {
            unregisterGeometry()
            BonsplitTabItemHitRegionRegistry.unregister(self)
        }

        func configure(tabId: UUID, geometryRegistry: TabBarItemGeometryRegistry) {
            if self.tabId != tabId || self.geometryRegistry !== geometryRegistry {
                unregisterGeometry()
                self.tabId = tabId
                self.geometryRegistry = geometryRegistry
            }
            registerGeometryIfVisible()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncHitBounds()
            BonsplitTabItemHitRegionRegistry.unregister(self)
            if window != nil {
                BonsplitTabItemHitRegionRegistry.register(self)
            }
            registerGeometryIfVisible()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview == nil {
                unregisterGeometry()
                BonsplitTabItemHitRegionRegistry.unregister(self)
            } else {
                registerGeometryIfVisible()
            }
        }

        override func layout() {
            super.layout()
            syncHitBounds()
            geometryRegistry?.geometryDidChange()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            syncHitBounds()
            geometryRegistry?.geometryDidChange()
        }

        override func setBoundsSize(_ newSize: NSSize) {
            super.setBoundsSize(newSize)
            syncHitBounds()
            geometryRegistry?.geometryDidChange()
        }

        override func setBoundsOrigin(_ newOrigin: NSPoint) {
            super.setBoundsOrigin(newOrigin)
            syncHitBounds()
            geometryRegistry?.geometryDidChange()
        }

        nonisolated func containsBonsplitTabItemHit(localPoint: NSPoint) -> Bool {
            hitBounds
                .insetBy(
                    dx: -BonsplitTabItemHitTesting.horizontalSlop,
                    dy: -BonsplitTabItemHitTesting.verticalSlop
                )
                .contains(localPoint)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func registerGeometryIfVisible() {
            guard window != nil, superview != nil, let tabId else { return }
            geometryRegistry?.register(self, for: tabId)
        }

        private func unregisterGeometry() {
            guard let tabId else { return }
            geometryRegistry?.unregister(self, for: tabId)
        }

        private func syncHitBounds() {
            hitBounds = bounds
        }
    }
}
