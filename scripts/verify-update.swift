import Foundation
import CryptoKit

struct InvalidUpdate: Error, CustomStringConvertible {
    let description: String
}

func verify() throws {
    let args = CommandLine.arguments
    guard args.count == 5 else {
        throw InvalidUpdate(description: "usage: verify-update.swift appcast.xml update.dmg version public-key")
    }
    let document = try XMLDocument(contentsOf: URL(fileURLWithPath: args[1]), options: [])
    let items = try document.nodes(forXPath: "/rss/channel/item")
    guard items.count == 1, let item = items.first as? XMLElement,
          item.elements(forName: "sparkle:version").first?.stringValue == args[3],
          item.elements(forName: "sparkle:channel").isEmpty,
          item.elements(forName: "description").first?.attribute(forName: "sparkle:format")?.stringValue == "plain-text",
          let enclosure = item.elements(forName: "enclosure").first,
          (enclosure.attribute(forName: "sparkle:installationType")?.stringValue ?? "application") == "application",
          enclosure.attribute(forName: "url")?.stringValue == "https://github.com/nethbotheju/Conure/releases/download/v\(args[3])/Conure-\(args[3]).dmg",
          let signatureString = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
          let signature = Data(base64Encoded: signatureString),
          let keyData = Data(base64Encoded: args[4]) else {
        throw InvalidUpdate(description: "Invalid stable update feed or missing archive signature")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: args[2]), options: .mappedIfSafe)
    guard enclosure.attribute(forName: "length")?.stringValue == String(data.count),
          try Curve25519.Signing.PublicKey(rawRepresentation: keyData).isValidSignature(signature, for: data) else {
        throw InvalidUpdate(description: "Update archive does not match its size or embedded publisher key")
    }
    print("Verified signed Conure \(args[3]) update archive and feed metadata")
}

do {
    try verify()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
