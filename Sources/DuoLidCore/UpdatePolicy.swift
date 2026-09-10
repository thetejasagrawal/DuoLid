import Foundation

public enum UpdatePolicy {
    public static let feedURL = "https://thetejasagrawal.github.io/DuoLid/appcast.xml"
    public static let repositoryURL = "https://github.com/thetejasagrawal/DuoLid"
    public static func allowedChannels(version: String, betaPreference: Bool?) -> Set<String> {
        let beta = betaPreference ?? version.contains("-beta")
        return beta ? ["beta"] : [] // Sparkle always includes the stable channel.
    }
    public static func validPublicKey(_ value: String?) -> Bool {
        guard let value, let bytes = Data(base64Encoded: value) else { return false }
        return bytes.count == 32
    }
}
