import Foundation

struct ModelLabel: Equatable {
    let name: String
    let engine: String?
    let shortName: String

    init(name: String, engine: String?) {
        self.name = name
        self.engine = engine
        shortName = Self.shorten(name)
    }

    static func shorten(_ name: String) -> String {
        let stripped = name.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }
}

enum ModelCatalog {
    static func label(for rawModelID: String, rows: [CLIModelRow]) -> ModelLabel {
        if let row = rows.first(where: { $0.id == rawModelID || $0.repo == rawModelID }) {
            return ModelLabel(name: row.name, engine: engineName(row.engine))
        }
        let fallback = rawModelID.split(separator: "/").last.map(String.init) ?? rawModelID
        return ModelLabel(name: fallback, engine: nil)
    }

    static func engineName(_ raw: String) -> String {
        raw == "fluidAudio" ? "FluidAudio" : "speech-swift"
    }
}
