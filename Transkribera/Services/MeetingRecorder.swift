import AVFoundation
import Foundation
import Observation
import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case noDisplay
    case nothingRecorded
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "Hittade ingen skärm att spela in ljud från. Kontrollera att en bildskärm är ansluten."
        case .nothingRecorded:
            return "Inget ljud spelades in. Kontrollera att ljud faktiskt spelades upp på datorn under inspelningen."
        case .permissionDenied:
            return "Transkribera behöver tillåtelse att spela in datorns ljud. Slå på Transkribera under Systeminställningar › Integritet och säkerhet › Skärm- och systemljudsinspelning och försök igen."
        }
    }
}

/// Spelar in datorns systemljud (t.ex. ett Meet/Teams-möte) via ScreenCaptureKit,
/// och på macOS 15+ även mikrofonen, till en M4A-fil.
@MainActor
@Observable
final class MeetingRecorder: NSObject {
    enum State: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case finishing
    }

    private(set) var state: State = .idle
    var errorMessage: String?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: CaptureOutput?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isBusy: Bool { state != .idle }

    /// Mikrofoninspelning via ScreenCaptureKit kräver macOS 15.
    static var supportsMicrophone: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    // MARK: - Start

    func start(includeMicrophone: Bool) async {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil

        do {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                throw RecordingError.permissionDenied
            }
            guard let display = content.displays.first else { throw RecordingError.noDisplay }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            // Vi behöver ingen video – håll bildflödet så litet och glest som möjligt.
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.showsCursor = false

            let base = AppPaths.recordingsDirectory.appending(path: UUID().uuidString)
            let systemWriter = try AudioSampleWriter(url: base.appendingPathExtension("system.m4a"), channels: 2)
            var micWriter: AudioSampleWriter?

            if includeMicrophone {
                if #available(macOS 15.0, *) {
                    configuration.captureMicrophone = true
                    if let device = AVCaptureDevice.default(for: .audio) {
                        configuration.microphoneCaptureDeviceID = device.uniqueID
                    }
                    micWriter = try AudioSampleWriter(url: base.appendingPathExtension("mic.m4a"), channels: 1)
                }
            }

            let output = CaptureOutput(systemWriter: systemWriter, microphoneWriter: micWriter)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
            if micWriter != nil {
                if #available(macOS 15.0, *) {
                    try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: output.queue)
                }
            }

            try await stream.startCapture()
            self.stream = stream
            self.output = output
            state = .recording(since: Date())
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
            stream = nil
            output = nil
        }
    }

    // MARK: - Stopp

    /// Stoppar inspelningen och returnerar URL till den färdiga ljudfilen.
    func stop() async -> URL? {
        guard isRecording, let stream, let output else { return nil }
        state = .finishing
        try? await stream.stopCapture()
        self.stream = nil
        self.output = nil

        defer { state = .idle }
        do {
            let files = await output.finish()
            guard !files.isEmpty else { throw RecordingError.nothingRecorded }
            if files.count == 1 { return files[0] }
            return try await Self.mix(files)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Mixar systemljud och mikrofon till en gemensam M4A-fil.
    private static func mix(_ files: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        for file in files {
            let asset = AVURLAsset(url: file)
            let duration = try await asset.load(.duration)
            for track in try await asset.loadTracks(withMediaType: .audio) {
                let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                try compositionTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: track,
                    at: .zero
                )
            }
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            return files[0]
        }
        let destination = AppPaths.recordingsDirectory.appending(path: "\(UUID().uuidString).m4a")
        export.outputURL = destination
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else {
            throw export.error ?? RecordingError.nothingRecorded
        }
        for file in files { try? FileManager.default.removeItem(at: file) }
        return destination
    }
}

extension MeetingRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "Inspelningen avbröts: \(error.localizedDescription)"
            self.stream = nil
            self.output = nil
            self.state = .idle
        }
    }
}

/// Tar emot ljudbuffertar från ScreenCaptureKit på en bakgrundskö.
private final class CaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "Transkribera.CaptureOutput")
    private let systemWriter: AudioSampleWriter
    private let microphoneWriter: AudioSampleWriter?

    init(systemWriter: AudioSampleWriter, microphoneWriter: AudioSampleWriter?) {
        self.systemWriter = systemWriter
        self.microphoneWriter = microphoneWriter
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            systemWriter.append(sampleBuffer)
        case .screen:
            break
        default:
            if #available(macOS 15.0, *) {
                if type == .microphone {
                    microphoneWriter?.append(sampleBuffer)
                }
            }
        }
    }

    /// Avslutar filerna och returnerar de som innehåller ljud.
    func finish() async -> [URL] {
        // Vänta in eventuella buffertar som redan ligger i kön.
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
        var urls: [URL] = []
        if let url = await systemWriter.finish() { urls.append(url) }
        if let url = await microphoneWriter?.finish() { urls.append(url) }
        return urls
    }
}

/// Skriver ljudbuffertar till en AAC-kodad M4A-fil.
private final class AudioSampleWriter: @unchecked Sendable {
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false

    init(url: URL, channels: Int) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000
        ]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func finish() async -> URL? {
        guard started else { return nil }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}
