import Foundation

/// Runs async jobs one at a time, in the order they were handed in. The CLI
/// reads, changes, and rewrites library.json with no lock, so two writes at
/// once could drop one of them.
@MainActor
public final class SerialRunner {
    private var tail: Task<Void, Never>?

    public init() {}

    /// Waits for every job handed in before this one, then runs it.
    @discardableResult
    public func run<T: Sendable>(_ job: @escaping @MainActor () async -> T) async -> T {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await job()
        }
        tail = Task { @MainActor in _ = await task.value }
        return await task.value
    }
}

/// The real library home, which tests and snapshots must never write to.
public enum LibraryHome {
    /// True for `~/.capture-director` or anything inside it.
    public static func isReal(_ path: String, userHome: String = NSHomeDirectory()) -> Bool {
        let real = URL(fileURLWithPath: userHome).appendingPathComponent(".capture-director").standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p == real || p.hasPrefix(real + "/")
    }
}

/// Remembers some defaults keys and puts them back later, so a test or
/// snapshot run leaves window frames and split-view widths as it found them.
public final class DefaultsGuard {
    private let defaults: UserDefaults
    private let prefixes: [String]
    private let saved: [String: Any]

    public init(_ defaults: UserDefaults, prefixes: [String]) {
        self.defaults = defaults
        self.prefixes = prefixes
        saved = Self.matching(defaults, prefixes)
    }

    /// Restores the saved values and removes matching keys that weren't there.
    public func restore() {
        for key in Self.matching(defaults, prefixes).keys where saved[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in saved { defaults.set(value, forKey: key) }
    }

    private static func matching(_ d: UserDefaults, _ prefixes: [String]) -> [String: Any] {
        // Only this app's own domain, not the global or argument domains.
        let domain = d.dictionaryRepresentation()
        return domain.filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
    }
}
