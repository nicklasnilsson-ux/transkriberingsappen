import Foundation

/// Formatering av tidsstämplar för gränssnitt och undertextformat.
public enum TimeFormatting {
    /// Kort format för gränssnittet: "01:23" eller "1:02:03" om över en timme.
    public static func short(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// SubRip-format: "00:01:23,456".
    public static func srt(_ seconds: Double) -> String {
        clock(seconds, separator: ",")
    }

    /// WebVTT-format: "00:01:23.456".
    public static func vtt(_ seconds: Double) -> String {
        clock(seconds, separator: ".")
    }

    private static func clock(_ seconds: Double, separator: String) -> String {
        let totalMillis = max(0, Int((seconds * 1000).rounded()))
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, millis)
    }

    /// Längd i läsbar form: "4 min 05 s" / "1 h 02 min".
    public static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d h %02d min", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%d min %02d s", minutes, secs)
        }
        return "\(secs) s"
    }
}
