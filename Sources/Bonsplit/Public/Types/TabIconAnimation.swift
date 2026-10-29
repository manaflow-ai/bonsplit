import Foundation

/// A consumer-supplied sequence of full-color PNG frames for a tab's leading icon.
///
/// Supply a new ``id`` whenever the frames or playback definition changes. Reusing
/// an ID preserves decoded images and playback progress across metadata updates.
/// The consumer owns payload bounds validation; empty or invalid sequences render
/// a static frame when possible instead of starting an animation.
///
/// ```swift
/// let animation = TabIconAnimation(
///     id: "activity-v1", frames: pngFrames, durations: [0.1, 0.2], loops: true
/// )
/// controller.updateTab(tabID, iconAnimation: .some(animation))
/// ```
public struct TabIconAnimation: Sendable, Hashable, Codable {
    /// Stable identity for this exact frame sequence and playback definition.
    public let id: String
    /// PNG-encoded frames, in playback order.
    public let frames: [Data]
    /// Display duration in seconds for each corresponding frame.
    public let durations: [TimeInterval]
    /// Whether playback repeats; otherwise the final frame remains visible.
    public let loops: Bool
    /// Frame shown with Reduce Motion enabled, clamped to the available frames.
    public let staticFrameIndex: Int

    /// Creates an animated tab icon without decoding its PNG frames.
    ///
    /// - Parameters:
    ///   - id: Identity that changes when the playback definition changes.
    ///   - frames: PNG data for each frame; an empty array renders no image.
    ///   - durations: Positive, finite durations, one per frame. Invalid durations disable playback.
    ///   - loops: Whether to repeat playback indefinitely.
    ///   - staticFrameIndex: Reduce Motion frame, defaulting to the first frame.
    public init(
        id: String,
        frames: [Data],
        durations: [TimeInterval],
        loops: Bool,
        staticFrameIndex: Int = 0
    ) {
        self.id = id
        self.frames = frames
        self.durations = durations
        self.loops = loops
        self.staticFrameIndex = staticFrameIndex
    }
}
