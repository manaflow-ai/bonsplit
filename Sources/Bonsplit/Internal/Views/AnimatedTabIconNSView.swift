import AppKit
import ImageIO
import QuartzCore

/// Decodes once per animation identity and delegates every frame transition to the render server.
@MainActor
final class AnimatedTabIconNSView: NSView {
    private static let animationKey = "tabIconContents"
    private let imageLayer = CALayer()
    private var animationID: String?
    private var definition: TabIconAnimation?
    private var images: [CGImage?] = []
    private var playback: CAKeyframeAnimation?
    private var observing = false
    private var reduceMotion = false
    private let workspace: NSWorkspace
    private let workspaceNotifications: NotificationCenter

    init(frame frameRect: NSRect, workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.workspaceNotifications = workspace.notificationCenter
        super.init(frame: frameRect)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        resetTimeline()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ animation: TabIconAnimation) {
        startObserving()
        guard animationID != animation.id else {
            let reduced = workspace.accessibilityDisplayShouldReduceMotion
            if reduced != reduceMotion { updateMotion(reduceMotion: reduced) }
            updateVisibility()
            return
        }
        animationID = animation.id
        definition = animation
        images = animation.frames.map { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        imageLayer.removeAnimation(forKey: Self.animationKey)
        resetTimeline()
        playback = makePlayback(animation)
        updateMotion(reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        updateVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateVisibility()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateVisibility()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateVisibility()
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        // AppKit's workspace and window lifecycle notifications arrive on the main thread.
        workspaceNotifications.addObserver(
            self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowVisibilityChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil
        )
    }

    func stopObserving() {
        workspaceNotifications.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        observing = false
        setPaused(true)
    }

    deinit {
        // Selector observers are weak; explicit removal also covers representable teardown.
        workspaceNotifications.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accessibilityOptionsChanged() {
        let newValue = workspace.accessibilityDisplayShouldReduceMotion
        guard newValue != reduceMotion else { return }
        updateMotion(reduceMotion: newValue)
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
        updateVisibility()
    }

    private func makePlayback(_ animation: TabIconAnimation) -> CAKeyframeAnimation? {
        let decoded = images.compactMap { $0 }
        guard decoded.count > 1,
              decoded.count == images.count,
              animation.durations.count == decoded.count,
              animation.durations.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let duration = animation.durations.reduce(0, +)
        guard duration.isFinite, duration > 0 else { return nil }
        var elapsed: TimeInterval = 0
        var keyTimes: [NSNumber] = animation.durations.map { frameDuration in
            defer { elapsed += frameDuration }
            return NSNumber(value: elapsed / duration)
        }
        keyTimes.append(1)
        let playback = CAKeyframeAnimation(keyPath: "contents")
        // Discrete values need a terminal key time to retain the last frame's duration.
        playback.values = decoded + [decoded[decoded.count - 1]]
        playback.keyTimes = keyTimes
        playback.calculationMode = .discrete
        playback.duration = duration
        playback.repeatCount = animation.loops ? .infinity : 0
        // Zero means "start now" to Core Animation; pin this to the original
        // layer timeline so restoring playback after Reduce Motion cannot restart it.
        playback.beginTime = .leastNonzeroMagnitude
        return playback
    }

    /// Reduced motion hides playback but preserves its logical position, including completion.
    func updateMotion(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        setPaused(true)
        imageLayer.removeAnimation(forKey: Self.animationKey)
        guard let definition else { return }
        let index = min(max(0, definition.staticFrameIndex), max(0, images.count - 1))
        let staticImage = images.indices.contains(index) ? images[index] : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = (reduceMotion || playback == nil || definition.loops)
            ? (staticImage ?? images.compactMap { $0 }.first)
            : images.last.flatMap { $0 }
        CATransaction.commit()
        if !reduceMotion, let playback,
           definition.loops || imageLayer.timeOffset < playback.duration {
            // Explicit beginTime preserves the same timeline when Reduce Motion is toggled.
            imageLayer.add(playback, forKey: Self.animationKey)
        }
        updateVisibility()
    }

    private func updateVisibility() {
        let visible = observing && window?.isVisible == true &&
            window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        setPaused(reduceMotion || !visible || playback == nil)
    }

    private func resetTimeline() {
        imageLayer.speed = 0
        imageLayer.timeOffset = 0
        imageLayer.beginTime = 0
    }

    private func setPaused(_ paused: Bool) {
        if paused {
            guard imageLayer.speed != 0 else { return }
            let elapsed = imageLayer.convertTime(CACurrentMediaTime(), from: nil)
            imageLayer.speed = 0
            imageLayer.timeOffset = elapsed
        } else {
            guard imageLayer.speed == 0 else { return }
            let elapsed = imageLayer.timeOffset
            imageLayer.speed = 1
            imageLayer.timeOffset = 0
            imageLayer.beginTime = 0
            imageLayer.beginTime = imageLayer.convertTime(CACurrentMediaTime(), from: nil) - elapsed
        }
    }

    var activeAnimation: CAKeyframeAnimation? {
        imageLayer.animation(forKey: Self.animationKey) as? CAKeyframeAnimation
    }

    var playbackLayer: CALayer { imageLayer }
}
