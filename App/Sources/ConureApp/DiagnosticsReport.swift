import Foundation
import Darwin

struct DiagnosticsModel: Sendable {
    let id: String
    let engine: String
    let state: String

    init(row: CLIModelRow) {
        id = DiagnosticsReport.allowed(row.id, pattern: #"[A-Za-z0-9][A-Za-z0-9._-]{0,99}"#)
        switch row.engine {
        case "speechSwift": engine = "speech-swift"
        case "fluidAudio": engine = "FluidAudio"
        default: engine = "Unavailable"
        }
        state = row.installState.rawValue
    }
}

struct DiagnosticsReport: Sendable {
    let appVersion: String
    let bundledCLIVersion: String
    let activeCLIVersion: String?
    let sourceCommit: String
    let buildURL: String?
    let macOSVersion: String
    let chip: String
    let models: [DiagnosticsModel]?

    init(
        appVersion: String?, bundledCLIVersion: String?, activeCLIVersion: String? = nil,
        usesExternalCLI: Bool = false, sourceCommit: String?, buildURL: String?,
        osVersion: OperatingSystemVersion, chip: String?, models: [CLIModelRow]?
    ) {
        let versionPattern = #"(?:[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?|x\.y\.z-dev)"#
        self.appVersion = Self.allowed(appVersion, pattern: versionPattern)
        self.bundledCLIVersion = Self.allowed(bundledCLIVersion, pattern: versionPattern)
        self.activeCLIVersion = usesExternalCLI ? Self.allowed(activeCLIVersion, pattern: versionPattern) : nil
        self.sourceCommit = Self.allowed(sourceCommit, pattern: #"[0-9a-fA-F]{7,64}"#)
        let safeURL = Self.allowed(buildURL, pattern: #"https://github\.com/nethbotheju/Conure/actions/runs/[0-9]+"#)
        self.buildURL = safeURL == "Unavailable" || safeURL == "[redacted]" ? nil : safeURL
        macOSVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        self.chip = Self.allowed(chip, pattern: #"Apple M[0-9]+(?: (?:Pro|Max|Ultra))?"#)
        self.models = models?.map(DiagnosticsModel.init).sorted { $0.id < $1.id }
    }

    var versionsMismatch: Bool? {
        guard !["Unavailable", "[redacted]"].contains(appVersion),
              !["Unavailable", "[redacted]"].contains(bundledCLIVersion) else { return nil }
        return appVersion != bundledCLIVersion
    }

    var versionStatus: String {
        switch versionsMismatch {
        case true: "WARNING: App and bundled CLI versions do not match."
        case false: "App and bundled CLI versions match."
        case nil: "App / bundled CLI version comparison unavailable."
        }
    }

    var text: String {
        var lines = [
            "Conure Diagnostics",
            "App version: \(appVersion)",
            "Bundled CLI version: \(bundledCLIVersion)",
            versionStatus,
        ]
        if let activeCLIVersion {
            lines += ["Model inventory uses an external / overridden CLI.", "Active CLI version: \(activeCLIVersion)"]
        }
        lines += ["Source commit: \(sourceCommit)"]
        if let buildURL { lines += ["Build run: \(buildURL)"] }
        lines += ["macOS: \(macOSVersion)", "Chip: \(chip)", "", "Models (active CLI):"]
        if let models {
            lines += models.isEmpty ? ["No models reported."] : models.map { "- \($0.id) | \($0.engine) | \($0.state)" }
        } else {
            lines += ["Unavailable (model inventory could not be read)."]
        }
        lines += ["", "Privacy: No transcripts, recording names, job details, file paths, or environment variables are included."]
        return lines.joined(separator: "\n")
    }

    static func allowed(_ value: String?, pattern: String) -> String {
        guard let value, !value.isEmpty else { return "Unavailable" }
        guard value.utf8.count <= 200,
              value.range(of: "\\A(?:\(pattern))\\z", options: .regularExpression) != nil else { return "[redacted]" }
        return value
    }
}

enum DiagnosticsSystem {
    static var chip: String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 0, size < 1024 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("machdep.cpu.brand_string", buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
