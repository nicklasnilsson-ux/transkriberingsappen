import Foundation
import SwiftData
import TranskriberaCore

/// En sparad version av texten, med rättningar och talarnamn, från före en "Transkribera igen"
/// eller från före man bytte till en annan version.
///
/// Texten som visas ligger alltid i `Transcript.segments`, så redigering, sök och export ser
/// ingen skillnad. Här ligger de andra versionerna som en packad kopia av segmenten. Byter man
/// version läggs den visade undan och den valda tas fram (se `Transcript.switchTo`).
@Model
final class TranscriptVersion {
    var id: UUID
    /// När versionen blev klar.
    var date: Date
    var modelName: String
    var language: String?
    var speakerCount: Int
    /// `VersionSnapshot`, JSON-kodad och packad.
    var snapshot: Data
    var transcript: Transcript?

    init(id: UUID = UUID(), date: Date, modelName: String, language: String?, speakerCount: Int, snapshot: Data) {
        self.id = id
        self.date = date
        self.modelName = modelName
        self.language = language
        self.speakerCount = speakerCount
        self.snapshot = snapshot
    }

    var segments: [SegmentData] {
        guard let data = Self.unpack(snapshot),
              let decoded = try? VersionSnapshot.decode(data) else { return [] }
        return decoded.segments
    }

    /// Packar och kodar segmenten för att spara dem. `nil` om det inte gick, och då sparas
    /// ingen version (hellre ingen version än en trasig).
    static func pack(_ segments: [SegmentData]) -> Data? {
        guard let json = try? VersionSnapshot(segments: segments).encoded(),
              let packed = try? (json as NSData).compressed(using: .lzfse) else { return nil }
        return packed as Data
    }

    static func unpack(_ data: Data) -> Data? {
        guard let unpacked = try? (data as NSData).decompressed(using: .lzfse) else { return nil }
        return unpacked as Data
    }
}

/// Information om en version som visas i titelkortet och i dialogen.
struct VersionInfo: Identifiable, Equatable {
    /// Den visade versionen har transkriptionens eget id; sparade har sitt eget.
    let id: UUID
    let date: Date
    let modelName: String
    let isShown: Bool
    /// 1 = äldst.
    let number: Int
}

extension Transcript {
    /// När texten som visas blev klar.
    var liveVersionDate: Date { versionDate ?? createdAt }

    private var slots: [VersionSlot] {
        [VersionSlot(id: id, date: liveVersionDate)] + versions.map { VersionSlot(id: $0.id, date: $0.date) }
    }

    /// Antal versioner, den visade inräknad. 0 när det inte finns någon text än.
    var versionCount: Int { segments.isEmpty ? 0 : versions.count + 1 }

    /// Alla versioner, äldst först.
    var versionInfos: [VersionInfo] {
        guard !segments.isEmpty else { return [] }
        let ordered = VersionHistory.ordered(slots)
        return ordered.enumerated().map { index, slot in
            let isShown = slot.id == id
            let model = isShown ? modelName : (versions.first { $0.id == slot.id }?.modelName ?? "")
            return VersionInfo(id: slot.id, date: slot.date, modelName: model, isShown: isShown, number: index + 1)
        }
    }

    /// Sant när det finns en nyare version än den som visas.
    var isViewingOlderVersion: Bool {
        versionCount > 1 && !VersionHistory.isLatest(id, in: slots)
    }

    /// Etiketten på den visade versionen, t.ex. "Version 2 av 4 · 14:32".
    var versionLabel: String? {
        guard versionCount > 1, let position = VersionHistory.position(of: id, in: slots) else { return nil }
        return VersionHistory.label(
            number: position.number,
            total: position.total,
            time: liveVersionDate.formatted(date: .omitted, time: .shortened)
        )
    }

    /// Beskrivning av den äldsta versionen till dialogen: "tid · modell".
    var oldestVersionDescription: String? {
        guard let oldest = versionInfos.first else { return nil }
        let when = oldest.date.formatted(date: .abbreviated, time: .shortened)
        return oldest.modelName.isEmpty ? when : "\(when) · \(RerunChange.baseModelName(oldest.modelName))"
    }

    /// Den senaste versionen visas inte: sparar den visade och tar fram `version`.
    /// Ingenting går förlorat; den visade versionen ligger kvar bland de sparade.
    func switchTo(_ version: TranscriptVersion, in context: ModelContext) {
        guard status == .completed || status == .failed else { return }
        let chosen = version.segments
        guard !chosen.isEmpty, let current = makeVersion(modelName: modelName, in: context) else { return }
        let chosenModel = version.modelName
        let chosenLanguage = version.language
        let chosenDate = version.date
        context.delete(version)
        versions.removeAll { $0.id == version.id }
        versions.append(current)
        replaceSegments(with: chosen, in: context)
        modelName = chosenModel
        language = chosenLanguage
        versionDate = chosenDate
    }

    /// Lägger en ny version överst när "Transkribera igen" blev klar. Den förra sparas, och de
    /// äldsta som inte får plats raderas först nu, när den nya finns (misslyckas körningen
    /// ändras ingenting). `previousModelName` är modellen som den förra texten gjordes med.
    func addNewVersion(
        _ output: TranscriptionOutput,
        previousModelName: String,
        in context: ModelContext,
        now: Date = Date()
    ) {
        if !segments.isEmpty, let previous = makeVersion(modelName: previousModelName, in: context) {
            versions.append(previous)
            let existing = versions.map { VersionSlot(id: $0.id, date: $0.date) }
            let dropped = Set(VersionHistory.idsToDrop(existing: existing))
            for old in versions where dropped.contains(old.id) { context.delete(old) }
            versions.removeAll { dropped.contains($0.id) }
        }
        replaceSegments(with: output.segments, in: context)
        language = output.language
        versionDate = now
    }

    /// En sparad kopia av texten som visas (inte tillagd i `versions` än).
    private func makeVersion(modelName: String, in context: ModelContext) -> TranscriptVersion? {
        guard let packed = TranscriptVersion.pack(segmentData) else { return nil }
        let version = TranscriptVersion(
            date: liveVersionDate,
            modelName: modelName,
            language: language,
            speakerCount: speakers.count,
            snapshot: packed
        )
        context.insert(version)
        return version
    }
}
