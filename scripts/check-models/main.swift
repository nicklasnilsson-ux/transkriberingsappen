// Skriver ut nedladdningskällan för varje modell som visas i väljaren, en per rad:
//   kb <asset> | klang <asset> | whisperkit <variant>
// Kompileras ihop med Transkribera/Models/ModelCatalog.swift av scripts/check-models.sh.

for model in WhisperModel.offered {
    switch model.source {
    case .kbRelease(let asset): print("kb \(asset)")
    case .pianissimoRelease(let asset): print("klang \(asset)")
    case .whisperKit(let variant): print("whisperkit \(variant)")
    }
}
