import Foundation

/// `Contents/Resources/config.json`, written by `capture-director install-app`.
public struct InstallConfig: Codable, Sendable, Equatable {
    public var node: String
    public var cli: String
    public var path: String
    public var cdHome: String?

    public init(node: String, cli: String, path: String, cdHome: String?) {
        self.node = node
        self.cli = cli
        self.path = path
        self.cdHome = cdHome
    }

    public static func load(from url: URL) throws -> InstallConfig {
        try JSONDecoder().decode(InstallConfig.self, from: Data(contentsOf: url))
    }

    /// The library home: the environment's CD_HOME, else the config's cdHome,
    /// else nil (callers fall back to ~/.capture-director).
    public static func effectiveHome(env: [String: String], configHome: String?) -> String? {
        if let h = env["CD_HOME"], !h.isEmpty { return h }
        if let h = configHome, !h.isEmpty { return h }
        return nil
    }
}
