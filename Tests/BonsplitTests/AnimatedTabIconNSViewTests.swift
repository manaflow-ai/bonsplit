import AppKit
import ImageIO
import QuartzCore
import Testing
import UniformTypeIdentifiers
@testable import Bonsplit

@Suite @MainActor
struct AnimatedTabIconNSViewTests {
    private func png(red: CGFloat) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func animation(id: String = "test", loops: Bool = true, staticFrameIndex: Int = 0) throws -> TabIconAnimation {
        TabIconAnimation(
            id: id, frames: [try png(red: 1), try png(red: 0)],
            durations: [0.1, 0.3], loops: loops, staticFrameIndex: staticFrameIndex
        )
    }

    @Test func keyframesUseDurationsAndDetachedViewIsPaused() throws {
        let view = AnimatedTabIconNSView(frame: .zero)
        view.configure(try animation())
        view.updateMotion(reduceMotion: false)
        let playback = try #require(view.activeAnimation)
        #expect(playback.keyPath == "contents")
        #expect(playback.calculationMode == .discrete)
        #expect(playback.keyTimes == [0, 0.25, 1])
        #expect(playback.duration == 0.4)
        #expect(playback.repeatCount == .infinity)
        #expect(view.playbackLayer.speed == 0)
        #expect(playback.values?.count == 3)
        #expect(view.hitTest(.zero) == nil)
        view.stopObserving()
    }

    @Test func sameIdentityRetainsDecodedImagesAndPlaybackPosition() throws {
        let view = AnimatedTabIconNSView(frame: .zero)
        let original = try animation()
        view.configure(original)
        let image = try #require(view.playbackLayer.contents as AnyObject?)
        view.playbackLayer.timeOffset = 0.2
        // Even a malformed replacement is not decoded until its identity changes.
        view.configure(TabIconAnimation(id: original.id, frames: [], durations: [], loops: false))
        #expect((view.playbackLayer.contents as AnyObject?) === image)
        #expect(view.playbackLayer.timeOffset == 0.2)
        view.configure(try animation(id: "new"))
        #expect(view.playbackLayer.timeOffset == 0)
        #expect((view.playbackLayer.contents as AnyObject?) !== image)
        view.stopObserving()
    }

    @Test func reduceMotionShowsSelectedFrameAndResumesWithoutRestarting() throws {
        let view = AnimatedTabIconNSView(frame: .zero)
        view.configure(try animation(staticFrameIndex: 1))
        view.updateMotion(reduceMotion: false)
        let playback = try #require(view.activeAnimation)
        let lastImage = try #require(playback.values?[1] as AnyObject?)
        view.playbackLayer.timeOffset = 0.2
        view.updateMotion(reduceMotion: true)
        #expect(view.activeAnimation == nil)
        #expect(view.playbackLayer.speed == 0)
        #expect((view.playbackLayer.contents as AnyObject?) === lastImage)
        view.updateMotion(reduceMotion: false)
        #expect(view.playbackLayer.timeOffset == 0.2)
        #expect(view.activeAnimation?.beginTime == playback.beginTime)
        view.stopObserving()
    }

    @Test func completedOneShotDoesNotReplayAndKeepsLastModelFrame() throws {
        let view = AnimatedTabIconNSView(frame: .zero)
        let definition = try animation(loops: false)
        view.configure(definition)
        view.updateMotion(reduceMotion: false)
        let playback = try #require(view.activeAnimation)
        let lastImage = try #require(playback.values?[1] as AnyObject?)
        #expect(playback.repeatCount == 0)
        #expect(playback.isRemovedOnCompletion)
        #expect((view.playbackLayer.contents as AnyObject?) === lastImage)
        // Advance the layer clock directly; no sleeps or frame-driven callbacks.
        view.playbackLayer.timeOffset = playback.duration + 0.1
        view.updateMotion(reduceMotion: true)
        view.updateMotion(reduceMotion: false)
        #expect(view.activeAnimation == nil)
        #expect((view.playbackLayer.contents as AnyObject?) === lastImage)
        view.stopObserving()
        view.configure(definition)
        #expect(view.activeAnimation == nil)
        #expect(view.playbackLayer.timeOffset > playback.duration)
        view.stopObserving()
    }

    @Test func emptyInvalidAndSingleFrameDefinitionsAreSafe() throws {
        let view = AnimatedTabIconNSView(frame: .zero)
        view.configure(TabIconAnimation(id: "empty", frames: [], durations: [], loops: true))
        #expect(view.activeAnimation == nil)
        #expect(view.playbackLayer.contents == nil)
        view.configure(TabIconAnimation(id: "single", frames: [try png(red: 1)], durations: [], loops: true, staticFrameIndex: .max))
        #expect(view.activeAnimation == nil)
        #expect(view.playbackLayer.contents != nil)
        let frames = try animation().frames
        for (index, durations) in [[0.1], [0, 1], [Double.nan, 1], [.infinity, 1], [-1, 1]].enumerated() {
            view.configure(TabIconAnimation(id: "invalid-\(index)", frames: frames, durations: durations, loops: true, staticFrameIndex: .min))
            #expect(view.activeAnimation == nil)
            #expect(view.playbackLayer.contents != nil)
        }
        view.configure(TabIconAnimation(id: "bad-png", frames: [Data([0]), frames[1]], durations: [0.1, 0.1], loops: true))
        #expect(view.activeAnimation == nil)
        #expect(view.playbackLayer.contents != nil)
        view.stopObserving()
    }

    @Test func hidingAndTeardownPauseWithoutDiscardingPosition() throws {
        let view = AnimatedTabIconNSView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
        view.configure(try animation())
        view.updateMotion(reduceMotion: false)
        view.playbackLayer.timeOffset = 0.2
        view.isHidden = true
        view.viewDidHide()
        view.layout()
        #expect(view.playbackLayer.speed == 0)
        #expect(view.playbackLayer.timeOffset == 0.2)
        #expect(view.playbackLayer.frame.size == CGSize(width: 14, height: 14))
        view.isHidden = false
        view.viewDidUnhide()
        #expect(view.playbackLayer.speed == 0, "Detached views remain paused even after unhiding")
        view.stopObserving()
        #expect(view.playbackLayer.timeOffset == 0.2)
    }
}
