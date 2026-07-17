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
    private struct ScrollMetrics {
        let offset: CGFloat
        let documentWidth: CGFloat
        let viewportWidth: CGFloat
        let unobscuredViewportWidth: CGFloat
    }

    private enum ScrollIntent: Equatable {
        case leading
        case revealSelectedTab(UUID)
    }

    private let itemViews = NSMapTable<NSUUID, NSView>.strongToWeakObjects()
    private let observers = NSHashTable<AnyObject>.weakObjects()
    private weak var scrollView: NSScrollView?
    private var scrollBoundsObserver: NSObjectProtocol?
    private var liveScrollObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?
    private var documentBoundsObserver: NSObjectProtocol?
    private var selectedTabId: UUID?
    private var lastObservedSelectedTabDocumentFrame: CGRect?
    private var pendingScrollIntent: ScrollIntent?
    private var expectedProgrammaticOffset: CGFloat?
    private var trailingObscuredWidth: CGFloat = 0

    deinit {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        if let liveScrollObserver {
            NotificationCenter.default.removeObserver(liveScrollObserver)
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
        }
        if let documentBoundsObserver {
            NotificationCenter.default.removeObserver(documentBoundsObserver)
        }
    }

    func register(_ view: NSView, for tabId: UUID) {
        itemViews.setObject(view, forKey: tabId as NSUUID)
        if tabId == selectedTabId {
            reconcilePendingScrollIntent()
        }
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
        if let liveScrollObserver {
            NotificationCenter.default.removeObserver(liveScrollObserver)
            self.liveScrollObserver = nil
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
            self.documentFrameObserver = nil
        }
        if let documentBoundsObserver {
            NotificationCenter.default.removeObserver(documentBoundsObserver)
            self.documentBoundsObserver = nil
        }
        expectedProgrammaticOffset = nil
        lastObservedSelectedTabDocumentFrame = nil
        self.scrollView = scrollView
        makeScrollStackTransparent(scrollView)
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
            Task { @MainActor [weak self] in
                self?.scrollBoundsDidChange()
            }
        }
        liveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.userWillScroll()
            }
        }
        if let documentView = scrollView?.documentView {
            documentView.postsFrameChangedNotifications = true
            documentView.postsBoundsChangedNotifications = true
            documentFrameObserver = makeDocumentGeometryObserver(
                name: NSView.frameDidChangeNotification,
                documentView: documentView
            )
            documentBoundsObserver = makeDocumentGeometryObserver(
                name: NSView.boundsDidChangeNotification,
                documentView: documentView
            )
        }
        if let selectedTabId {
            pendingScrollIntent = .revealSelectedTab(selectedTabId)
        }
        invalidateObservers()
        reconcilePendingScrollIntent()
        enforceLeadingEdgeIfContentFits()
    }

    /// Records the selected tab as a viewport intent until live AppKit geometry can satisfy it.
    func revealSelection(_ tabId: UUID?) {
        if selectedTabId != tabId {
            lastObservedSelectedTabDocumentFrame = nil
        }
        selectedTabId = tabId
        pendingScrollIntent = tabId.map(ScrollIntent.revealSelectedTab) ?? .leading
        reconcilePendingScrollIntent()
    }

    /// Updates the portion of the clip view covered by trailing foreground controls.
    func setTrailingObscuredWidth(_ width: CGFloat) {
        let normalizedWidth = max(0, width)
        guard abs(normalizedWidth - trailingObscuredWidth) > 0.5 else { return }

        trailingObscuredWidth = normalizedWidth
        pendingScrollIntent = selectedTabId.map(ScrollIntent.revealSelectedTab) ?? .leading
        reconcilePendingScrollIntent()
        invalidateObservers()
    }

    /// Preserves a resize's current anchor while keeping the clip view inside its valid range.
    func viewportLayoutDidChange() {
        guard let metrics = currentScrollMetrics(), metrics.viewportWidth > 0 else { return }
        guard !TabBarStyling.shouldKeepLeadingAligned(
            contentWidth: metrics.documentWidth,
            containerWidth: metrics.viewportWidth
        ) else {
            setHorizontalOffset(0, metrics: metrics)
            return
        }

        let maximumOffset = max(0, metrics.documentWidth - metrics.viewportWidth)
        let clampedOffset = min(max(metrics.offset, 0), maximumOffset)
        setHorizontalOffset(clampedOffset, metrics: metrics)
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

    func geometryDidChange(for tabId: UUID) {
        if tabId == selectedTabId {
            if selectedTabFrameDidChange(tabId) {
                pendingScrollIntent = .revealSelectedTab(tabId)
            }
            reconcilePendingScrollIntent()
        }
        invalidateObservers()
    }

    private func scrollBoundsDidChange() {
        if let expectedProgrammaticOffset,
           let metrics = currentScrollMetrics(),
           abs(metrics.offset - expectedProgrammaticOffset) > 0.5 {
            setHorizontalOffset(expectedProgrammaticOffset, metrics: metrics)
        }
        invalidateObservers()
    }

    private func userWillScroll() {
        expectedProgrammaticOffset = nil
        pendingScrollIntent = nil
    }

    private func selectedTabFrameDidChange(_ tabId: UUID) -> Bool {
        guard let scrollView,
              let documentView = scrollView.documentView,
              let itemView = itemViews.object(forKey: tabId as NSUUID),
              itemView.window === scrollView.window,
              isVisibleInHierarchy(itemView) else {
            return false
        }

        let currentFrame = itemView.convert(itemView.bounds, to: documentView)
        defer { lastObservedSelectedTabDocumentFrame = currentFrame }
        guard let previousFrame = lastObservedSelectedTabDocumentFrame else { return true }
        return abs(currentFrame.minX - previousFrame.minX) > 0.5
            || abs(currentFrame.maxX - previousFrame.maxX) > 0.5
    }

    private func reconcilePendingScrollIntent() {
        guard let intent = pendingScrollIntent else { return }

        let didReconcile: Bool
        switch intent {
        case .leading:
            didReconcile = scrollToLeadingEdgeIfReady()
        case .revealSelectedTab(let tabId):
            didReconcile = revealTabIfClipped(tabId)
        }

        if didReconcile, pendingScrollIntent == intent {
            pendingScrollIntent = nil
        }
    }

    private func makeDocumentGeometryObserver(
        name: Notification.Name,
        documentView: NSView
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name,
            object: documentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.documentGeometryDidChange()
            }
        }
    }

    private func documentGeometryDidChange() {
        pendingScrollIntent = selectedTabId.map(ScrollIntent.revealSelectedTab) ?? .leading
        viewportLayoutDidChange()
        invalidateObservers()
    }

    @discardableResult
    private func scrollToLeadingEdgeIfReady() -> Bool {
        guard let metrics = currentScrollMetrics(), metrics.viewportWidth > 0 else { return false }
        setHorizontalOffset(0, metrics: metrics)
        return true
    }

    @discardableResult
    private func revealTabIfClipped(_ tabId: UUID) -> Bool {
        guard let scrollView,
              let documentView = scrollView.documentView,
              let itemView = itemViews.object(forKey: tabId as NSUUID),
              itemView.window === scrollView.window,
              isVisibleInHierarchy(itemView),
              let metrics = currentScrollMetrics(),
              metrics.unobscuredViewportWidth > 0 else {
            return false
        }

        let itemFrame = itemView.convert(itemView.bounds, to: documentView)
        guard itemFrame.width > 0,
              itemFrame.minX >= -0.5,
              itemFrame.maxX <= metrics.documentWidth + 0.5 else {
            return false
        }
        lastObservedSelectedTabDocumentFrame = itemFrame

        if TabBarStyling.shouldKeepLeadingAligned(
            contentWidth: metrics.documentWidth,
            containerWidth: metrics.viewportWidth
        ) {
            setHorizontalOffset(0, metrics: metrics)
            return true
        }

        let visibleRange = metrics.offset...(metrics.offset + metrics.unobscuredViewportWidth)
        guard itemFrame.minX < visibleRange.lowerBound - 0.5
                || itemFrame.maxX > visibleRange.upperBound + 0.5 else {
            setHorizontalOffset(metrics.offset, metrics: metrics)
            return true
        }

        let maximumOffset = max(0, metrics.documentWidth - metrics.viewportWidth)
        let centeredOffset = itemFrame.midX - (metrics.unobscuredViewportWidth / 2)
        let targetOffset = min(max(centeredOffset, 0), maximumOffset)
        setHorizontalOffset(targetOffset, metrics: metrics)
        return true
    }

    private func currentScrollMetrics() -> ScrollMetrics? {
        guard let scrollView else { return nil }
        let clipView = scrollView.contentView
        let documentWidth = max(
            scrollView.documentView?.frame.width ?? 0,
            scrollView.documentView?.bounds.width ?? 0
        )
        return ScrollMetrics(
            offset: clipView.bounds.origin.x,
            documentWidth: documentWidth,
            viewportWidth: clipView.bounds.width,
            unobscuredViewportWidth: max(0, clipView.bounds.width - trailingObscuredWidth)
        )
    }

    private func enforceLeadingEdgeIfContentFits() {
        guard let metrics = currentScrollMetrics(), metrics.viewportWidth > 0 else { return }
        guard TabBarStyling.shouldKeepLeadingAligned(
            contentWidth: metrics.documentWidth,
            containerWidth: metrics.viewportWidth
        ) else {
            return
        }
        setHorizontalOffset(0, metrics: metrics)
    }

    private func setHorizontalOffset(_ targetOffset: CGFloat, metrics: ScrollMetrics) {
        let maximumOffset = max(0, metrics.documentWidth - metrics.viewportWidth)
        let clampedOffset = min(max(targetOffset, 0), maximumOffset)
        expectedProgrammaticOffset = clampedOffset
        guard abs(clampedOffset - metrics.offset) > 0.5, let scrollView else { return }
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: clampedOffset, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func makeScrollStackTransparent(_ scrollView: NSScrollView?) {
        scrollView?.drawsBackground = false
        scrollView?.backgroundColor = .clear
        scrollView?.wantsLayer = true
        scrollView?.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView?.layer?.isOpaque = false

        let clipView = scrollView?.contentView
        clipView?.drawsBackground = false
        clipView?.backgroundColor = .clear
        clipView?.wantsLayer = true
        clipView?.layer?.backgroundColor = NSColor.clear.cgColor
        clipView?.layer?.isOpaque = false

        scrollView?.documentView?.wantsLayer = true
        scrollView?.documentView?.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView?.documentView?.layer?.isOpaque = false
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
        private var hitBounds: NSRect = .zero
        private var tabId: UUID?
        private weak var geometryRegistry: TabBarItemGeometryRegistry?
        private var containerFrameObserver: NSObjectProtocol?
        private var containerBoundsObserver: NSObjectProtocol?

        override var mouseDownCanMoveWindow: Bool { false }

        deinit {
            invalidateContainerGeometryObservers()
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
            observeContainerGeometry()
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
            notifyGeometryDidChange()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            syncHitBounds()
            notifyGeometryDidChange()
        }

        override func setBoundsSize(_ newSize: NSSize) {
            super.setBoundsSize(newSize)
            syncHitBounds()
            notifyGeometryDidChange()
        }

        override func setBoundsOrigin(_ newOrigin: NSPoint) {
            super.setBoundsOrigin(newOrigin)
            syncHitBounds()
            notifyGeometryDidChange()
        }

        func containsBonsplitTabItemHit(localPoint: NSPoint) -> Bool {
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
            geometryRegistry?.attachScrollView(enclosingScrollView)
            geometryRegistry?.register(self, for: tabId)
        }

        private func unregisterGeometry() {
            guard let tabId else { return }
            geometryRegistry?.unregister(self, for: tabId)
        }

        private func observeContainerGeometry() {
            invalidateContainerGeometryObservers()
            guard let containerView = superview else { return }
            containerView.postsFrameChangedNotifications = true
            containerView.postsBoundsChangedNotifications = true
            containerFrameObserver = makeContainerGeometryObserver(
                name: NSView.frameDidChangeNotification,
                containerView: containerView
            )
            containerBoundsObserver = makeContainerGeometryObserver(
                name: NSView.boundsDidChangeNotification,
                containerView: containerView
            )
        }

        private func makeContainerGeometryObserver(
            name: Notification.Name,
            containerView: NSView
        ) -> NSObjectProtocol {
            NotificationCenter.default.addObserver(
                forName: name,
                object: containerView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.notifyGeometryDidChange()
                }
            }
        }

        private func invalidateContainerGeometryObservers() {
            if let containerFrameObserver {
                NotificationCenter.default.removeObserver(containerFrameObserver)
                self.containerFrameObserver = nil
            }
            if let containerBoundsObserver {
                NotificationCenter.default.removeObserver(containerBoundsObserver)
                self.containerBoundsObserver = nil
            }
        }

        private func notifyGeometryDidChange() {
            guard let tabId else { return }
            geometryRegistry?.geometryDidChange(for: tabId)
        }

        private func syncHitBounds() {
            hitBounds = bounds
        }
    }
}
