import Foundation
import Combine

enum SidebarDestination: String, CaseIterable, Identifiable {
    case upload
    case queue
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: return "Upload"
        case .queue: return "Queue"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var isWorkspace: Bool { self != .settings }

    var systemImage: String {
        switch self {
        case .upload: return "square.and.arrow.down"
        case .queue: return "list.bullet"
        case .library: return "books.vertical"
        case .settings: return "gearshape"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case models
    case general
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: return "Models"
        case .general: return "General"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    static let destinationKey = "conure.sidebar.destination"

    @Published var destination: SidebarDestination {
        didSet { defaults.set(destination.rawValue, forKey: Self.destinationKey) }
    }
    @Published var settingsTab: SettingsTab = .models

    @Published private(set) var pendingUploads: [URL] = []
    @Published private(set) var pendingNotice: String?

    let restoredFromDefaults: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.destinationKey)
            .flatMap(SidebarDestination.init(rawValue:))
        restoredFromDefaults = stored != nil
        destination = stored ?? .queue
    }

    func go(to destination: SidebarDestination) {
        self.destination = destination
    }

    func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        destination = .settings
    }

    func beginUpload(with urls: [URL], notice: String? = nil) {
        var known = Set(pendingUploads.map { $0.standardizedFileURL.path })
        let fresh = urls.filter { known.insert($0.standardizedFileURL.path).inserted }
        pendingUploads.append(contentsOf: fresh)
        pendingNotice = notice
        destination = .upload
    }

    func consumeUploads() -> (urls: [URL], notice: String?) {
        let result = (pendingUploads, pendingNotice)
        pendingUploads = []
        pendingNotice = nil
        return result
    }
}
