import Foundation
@preconcurrency import ScreenCaptureKit

final class WindowRecording {
    let path: String
    private let stream: SCStream
    private let events: RecordingEvents

    private init(path: String, stream: SCStream, events: RecordingEvents) {
        self.path = path
        self.stream = stream
        self.events = events
    }

    static func start(_ window: SCWindow, to path: String) async throws -> WindowRecording {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.capturesAudio = true

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = URL(filePath: path)
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .hevc

        let events = RecordingEvents()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recordingConfiguration, delegate: events))
        let failure: (any Error)? = await waitAtMost(.seconds(5), orReturn: CaptureError.timedOut) { done in
            stream.startCapture { done($0) }
        }
        if let failure { throw failure }
        return WindowRecording(path: path, stream: stream, events: events)
    }

    func finish() async throws {
        let stream = stream
        await waitAtMost(.seconds(5), orReturn: ()) { done in
            stream.stopCapture { _ in done(()) }
        }
        switch await events.next(within: .seconds(5)) {
        case .finished:
            return
        case .failed(let error):
            throw error
        case nil:
            throw CaptureError.timedOut
        }
    }
}

enum CaptureError: LocalizedError {
    case timedOut

    var errorDescription: String? { "screen capture didn't respond in time" }
}

func listWindows() async -> [SCWindow]? {
    await waitAtMost(.seconds(5), orReturn: nil) { done in
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            done(content?.windows)
        }
    }
}

private final class RecordingEvents: NSObject, SCRecordingOutputDelegate, Sendable {
    enum Event {
        case finished
        case failed(any Error)
    }

    private let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    override init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        continuation.yield(.finished)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        continuation.yield(.failed(error))
    }

    func next(within timeout: Duration) async -> Event? {
        await withTaskGroup(of: Event?.self) { group in
            group.addTask {
                var iterator = self.events.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }
}

// ScreenCaptureKit crashes without this in a command-line tool.
func connectToWindowServer() {
    _ = CGMainDisplayID()
}
