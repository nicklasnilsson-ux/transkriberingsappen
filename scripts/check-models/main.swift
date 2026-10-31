import Foundation

// Skriver ut nedladdningskällan för varje modell som visas i väljaren, en per rad:
//   kb <asset> | klang <asset> | whisperkit <variant>
// Kompileras ihop med Transkribera/Models/ModelCatalog.swift av scripts/check-models.sh.

// Reglerna för modellväljaren. Bryts en av dem stoppas bygget.
var problems: [String] = []
if WhisperModel.offered.first != WhisperModel.default {
    problems.append("Standardmodellen ska vara först i väljaren")
}
for model in WhisperModel.allCases {
    let expected: WhisperModel = model.isHidden ? .default : model
    if WhisperModel.resolved(model.rawValue) != expected {
        problems.append("En sparad inställning på \(model.rawValue) ger fel modell")
    }
}
if WhisperModel.resolved(nil) != .default || WhisperModel.resolved("finns-inte") != .default {
    problems.append("Saknad eller okänd modell ska ge standardmodellen")
}
if !problems.isEmpty {
    for problem in problems { FileHandle.standardError.write(Data("::error::\(problem)\n".utf8)) }
    exit(1)
}

for model in WhisperModel.offered {
    switch model.source {
    case .kbRelease(let asset): print("kb \(asset)")
    case .pianissimoRelease(let asset): print("klang \(asset)")
    case .whisperKit(let variant): print("whisperkit \(variant)")
    }
}
