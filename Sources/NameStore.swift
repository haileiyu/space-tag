import Foundation

extension Notification.Name {
    static let spaceNamesChanged = Notification.Name("spaceNamesChanged")
}

/// Space names, saved in UserDefaults and keyed by Space UUID.
final class NameStore {
    static let shared = NameStore()
    private let defaultsKey = "spaceNames"
    private var names: [String: String]

    private init() {
        names = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func name(for space: Space) -> String? { names[space.key] }

    func displayName(for space: Space) -> String { name(for: space) ?? space.defaultName }

    func setName(_ name: String?, for space: Space) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        names[space.key] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(names, forKey: defaultsKey)
        NotificationCenter.default.post(name: .spaceNamesChanged, object: nil)
    }
}
