import Foundation

struct StableVersion: Comparable, Sendable {
    let components: [String]

    init?(_ value: String) {
        let parts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard identifiers.allSatisfy({ identifier in
                !identifier.isEmpty && identifier.utf8.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
                }
            }) else { return nil }
        }
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3, numbers.allSatisfy({ number in
            !number.isEmpty && number.utf8.allSatisfy { (48...57).contains($0) }
                && (number.count == 1 || number.first != "0")
        }) else { return nil }
        components = numbers.map(String.init)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) where left != right {
            return left.count == right.count ? left < right : left.count < right.count
        }
        return false
    }
}

struct UpdateConfiguration {
    static let feedURL = "https://github.com/nethbotheju/Conure/releases/latest/download/appcast.xml"
    static let releasesURL = URL(string: "https://github.com/nethbotheju/Conure/releases")!

    let version: String?
    let bundleIdentifier: String?
    let publicKey: String?
    let feedURL: String?
    let isAppBundle: Bool
    let requiresSignedFeed: Bool
    let verifiesBeforeExtraction: Bool

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        bundleIdentifier = bundle.bundleIdentifier
        publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        isAppBundle = bundle.bundleURL.pathExtension == "app"
        requiresSignedFeed = bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true
        verifiesBeforeExtraction = bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true
    }

    init(version: String?, bundleIdentifier: String?, publicKey: String?, feedURL: String?,
         isAppBundle: Bool, requiresSignedFeed: Bool, verifiesBeforeExtraction: Bool) {
        self.version = version
        self.bundleIdentifier = bundleIdentifier
        self.publicKey = publicKey
        self.feedURL = feedURL
        self.isAppBundle = isAppBundle
        self.requiresSignedFeed = requiresSignedFeed
        self.verifiesBeforeExtraction = verifiesBeforeExtraction
    }

    var disabledReason: String? {
        if bundleIdentifier == "com.conure.app.dev" {
            return "Conure Dev uses manual GitHub Actions artifact installs. Stable in-app updates are disabled and never replace either app."
        }
        guard bundleIdentifier == "com.conure.app", isAppBundle,
              let version, StableVersion(version) != nil else {
            return "In-app updates require a packaged stable Conure app. Development, prerelease, and unpackaged builds do not check for stable updates."
        }
        guard let publicKey, Data(base64Encoded: publicKey)?.count == 32,
              feedURL == Self.feedURL, requiresSignedFeed, verifiesBeforeExtraction else {
            return "Secure updates are not configured in this build. The publisher must configure an update-signing key. You can still install an official release manually."
        }
        return nil
    }
}

struct UpdateOffer: Equatable {
    let version: String
    let notes: String?

    var releaseURL: URL {
        URL(string: "https://github.com/nethbotheju/Conure/releases/tag/v\(version)")!
    }
}

enum UpdatePolicy {
    static func accepts(version: String, installedVersion: String, url: URL?, channel: String?,
                        installationType: String, feedIsSigned: Bool) -> Bool {
        guard feedIsSigned, channel == nil, installationType == "application",
              let candidate = StableVersion(version), let installed = StableVersion(installedVersion),
              candidate > installed else { return false }
        return url?.absoluteString == "https://github.com/nethbotheju/Conure/releases/download/v\(version)/Conure-\(version).dmg"
    }
}
