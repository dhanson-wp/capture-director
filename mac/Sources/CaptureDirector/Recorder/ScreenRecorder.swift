import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Films only the target app's windows, on a solid background, into a 3840x2160 movie.
final class ScreenRecorder {
    nonisolated static let width = 3840
    nonisolated static let height = 2160

    private let url: URL
    private let sink: FrameSink
    private var stream: SCStream?

    init(url: URL, fps: Int) throws {
        self.url = url
        sink = try FrameSink(url: url, fps: fps)
    }

    /// Starts filming. `sourceRect` is in the main display's points (top-left origin),
    /// which match global screen points because the main display sits at the origin.
    func start(pid: pid_t, sourceRect: CGRect, background: CGColor, fps: Int) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw RecorderError("I couldn't read what's on screen: \(error.localizedDescription)")
        }
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw RecorderError("I couldn't find the main display.")
        }
        guard let app = content.applications.first(where: { $0.processID == pid }) else {
            throw RecorderError("I couldn't find the app's windows to record.")
        }
        // Only this one process's windows (its main window, sheets, popovers, and menus).
        // Everything else, wallpaper included, is left out and replaced by the background color.
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Self.width
        config.height = Self.height
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.backgroundColor = background
        config.showsCursor = false
        config.ignoreShadowsDisplay = false
        config.capturesAudio = false
        config.queueDepth = 8

        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            try sink.startWriting()
            try await stream.startCapture()
        } catch let error as RecorderError {
            throw error
        } catch {
            throw RecorderError("The screen recording didn't start: \(error.localizedDescription)")
        }
        self.stream = stream
    }

    /// Waits for the first frame and returns its time in host seconds: the capture's zero.
    func firstFrame(timeout: Double = 3) async throws -> Double {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let error = sink.failure { throw RecorderError("The screen recording stopped: \(error.localizedDescription)") }
            if let start = sink.startTime { return start.seconds }
            try? await Task.sleep(for: .milliseconds(10))
        }
        throw RecorderError("The screen recording didn't start.")
    }

    /// Stops filming and closes the movie so it runs until `end` (host seconds), even if the
    /// screen was still and the last frame came earlier.
    func finish(at end: Double) async throws {
        await stop()
        if let error = sink.failure { throw RecorderError("The screen recording stopped: \(error.localizedDescription)") }
        try await sink.finish(at: CMTime(seconds: end, preferredTimescale: 600_000))
    }

    /// The written movie's real length in seconds.
    func duration() async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// Stops the stream if it's running. Safe to call more than once.
    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    /// Abandons the movie.
    func cancel() {
        sink.cancel()
    }
}

/// Receives frames on its own queue and appends them to the movie.
private nonisolated final class FrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "capture-director.frames")
    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var first: CMTime?
    private var last: CMTime?
    private var stopError: Error?
    private var closed = false

    init(url: URL, fps: Int) throws {
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecorderError("I couldn't create \(url.lastPathComponent): \(error.localizedDescription)")
        }
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ScreenRecorder.width,
            AVVideoHeightKey: ScreenRecorder.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 80_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        super.init()
        guard writer.canAdd(input) else { throw RecorderError("I couldn't set up the movie writer.") }
        writer.add(input)
    }

    func startWriting() throws {
        guard writer.startWriting() else {
            throw RecorderError("I couldn't start writing the movie: \(writer.error?.localizedDescription ?? "unknown error").")
        }
    }

    var startTime: CMTime? { lock.withLock { first } }

    var failure: Error? {
        lock.withLock { stopError ?? (writer.status == .failed ? writer.error : nil) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer) else { return }
        lock.withLock {
            guard !closed, writer.status == .writing else { return }
            let time = sampleBuffer.presentationTimeStamp
            if first == nil {
                writer.startSession(atSourceTime: time)
                first = time
            }
            if input.isReadyForMoreMediaData, input.append(sampleBuffer) { last = time }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { stopError = error }
    }

    func finish(at end: CMTime) async throws {
        let ready: Bool = lock.withLock {
            closed = true
            guard first != nil, writer.status == .writing else { return false }
            input.markAsFinished()
            writer.endSession(atSourceTime: last.map { CMTimeMaximum($0, end) } ?? end)
            return true
        }
        guard ready else {
            throw RecorderError("The screen recording didn't capture any frames.")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw RecorderError("I couldn't finish the movie: \(writer.error?.localizedDescription ?? "unknown error").")
        }
    }

    func cancel() {
        lock.withLock {
            closed = true
            if writer.status == .writing { writer.cancelWriting() }
        }
    }

    /// Screen frames also arrive for idle and blank moments with no new image; only complete ones carry pixels.
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
