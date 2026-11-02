import Foundation

/// Skäl till att transkriberingskön väntar med att starta nästa fil. Ett skäl räcker.
/// Filer som släpps under en mötesinspelning köas men startar först när inspelningen är sparad,
/// så att transkriberingen inte tar kraft från inspelningen.
public struct QueueHolds: Equatable, Sendable {
    /// Testlabbet använder transkriberaren.
    public var testLab = false
    /// En mötesinspelning pågår (startar, spelar in eller sparas).
    public var recording = false

    public init(testLab: Bool = false, recording: Bool = false) {
        self.testLab = testLab
        self.recording = recording
    }

    public var isHeld: Bool { testLab || recording }
}

/// Vad en släppt eller öppnad fil får göra med vyn.
public enum ImportNavigation {
    /// Under en inspelning får importen inte byta läge eller markering. Då försvinner
    /// Stoppa-knappen, som bara finns i mötesläget.
    public static func shouldNavigate(recordingBusy: Bool) -> Bool { !recordingBusy }
}
