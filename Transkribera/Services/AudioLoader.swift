import AVFoundation
import Foundation

enum AudioLoaderError: LocalizedError {
    case noAudioTrack
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "Filen innehåller inget ljudspår."
        case .readFailed(let reason): return "Kunde inte läsa ljudet: \(reason)"
        }
    }
}

struct MediaInfo {
    var duration: Double
    var isVideo: Bool
}

/// Läser ljud ur valfri ljud- eller videofil som AVFoundation kan öppna
/// (MP4, MOV, M4A, MP3, WAV, AIFF …) och konverterar det till 16 kHz mono
/// Float-samples, vilket är vad Whisper och SpeakerKit vill ha.
enum AudioLoader {
    static let sampleRate: Double = 16_000

    static func mediaInfo(for url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw AudioLoaderError.noAudioTrack }
        return MediaInfo(duration: duration.isFinite ? duration : 0, isVideo: !videoTracks.isEmpty)
    }

    /// Läser och mixar alla ljudspår till ett 16 kHz monospår.
    static func loadSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw AudioLoaderError.noAudioTrack }

        return try await Task.detached(priority: .userInitiated) {
            try readSamples(asset: asset, tracks: tracks)
        }.value
    }

    private static func readSamples(asset: AVAsset, tracks: [AVAssetTrack]) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AudioLoaderError.readFailed("Ljudformatet stöds inte.")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw AudioLoaderError.readFailed(reader.error?.localizedDescription ?? "okänt fel")
        }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let chunk = [Float](unsafeUninitializedCapacity: count) { buffer, initializedCount in
                let status = CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: count * MemoryLayout<Float>.size,
                    destination: buffer.baseAddress!
                )
                initializedCount = status == kCMBlockBufferNoErr ? count : 0
            }
            samples.append(contentsOf: chunk)
        }

        if reader.status == .failed {
            throw AudioLoaderError.readFailed(reader.error?.localizedDescription ?? "okänt fel")
        }
        return samples
    }
}
