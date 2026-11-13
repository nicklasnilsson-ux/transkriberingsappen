import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

// Användning: mlx-pianissimo <hf-repo> <ljud.wav> [fp32]
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Användning: mlx-pianissimo <hf-repo> <ljud.wav> [fp32]")
    exit(2)
}
let repo = args[1]
let audioURL = URL(fileURLWithPath: args[2])
let dtype: DType? = args.count > 3 && args[3] == "fp32" ? .float32 : nil

let loadStart = Date()
let model = try await ParakeetModel.fromPretrained(repo, computeDType: dtype)
let loadTime = Date().timeIntervalSince(loadStart)

let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16000)
let start = Date()
let output = model.generate(audio: audio)
let time = Date().timeIntervalSince(start)
print("MODELL: \(repo)")
print("LADDNING: \(String(format: "%.1f", loadTime)) s, TRANSKRIBERING: \(String(format: "%.2f", time)) s")
print("TEXT: \(output.text)")
