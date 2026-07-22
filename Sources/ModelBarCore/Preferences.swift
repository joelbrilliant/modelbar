import Foundation

public enum RefreshInterval: Int, CaseIterable, Codable, Equatable, Sendable {
    case manual = 0
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case sixtyMinutes = 3_600

    public var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .fifteenMinutes:
            return "Every 15 minutes"
        case .thirtyMinutes:
            return "Every 30 minutes"
        case .sixtyMinutes:
            return "Every 60 minutes"
        }
    }

    public var seconds: TimeInterval? {
        self == .manual ? nil : TimeInterval(rawValue)
    }
}

public struct ModelBarPreferences: Codable, Equatable, Sendable {
    public var disabledProviderIDs: Set<String>
    public var hiddenAgentIDs: Set<String>
    public var refreshInterval: RefreshInterval

    public init(
        disabledProviderIDs: Set<String> = [],
        hiddenAgentIDs: Set<String> = [],
        refreshInterval: RefreshInterval = .fifteenMinutes
    ) {
        self.disabledProviderIDs = disabledProviderIDs
        self.hiddenAgentIDs = hiddenAgentIDs
        self.refreshInterval = refreshInterval
    }

    public func isProviderEnabled(_ id: String) -> Bool {
        !disabledProviderIDs.contains(id)
    }

    public func isAgentVisible(_ id: String) -> Bool {
        !hiddenAgentIDs.contains(id)
    }
}

public final class PreferencesStore {
    private enum Keys {
        static let disabledProviders = "disabledProviderIDs"
        static let hiddenAgents = "hiddenAgentIDs"
        static let refreshInterval = "refreshInterval"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ModelBarPreferences {
        let disabled = Set(defaults.stringArray(forKey: Keys.disabledProviders) ?? [])
        let hidden = Set(defaults.stringArray(forKey: Keys.hiddenAgents) ?? [])
        let storedInterval = defaults.object(forKey: Keys.refreshInterval) as? Int
        let interval = storedInterval.flatMap(RefreshInterval.init(rawValue:))
            ?? .fifteenMinutes
        return ModelBarPreferences(
            disabledProviderIDs: disabled,
            hiddenAgentIDs: hidden,
            refreshInterval: interval
        )
    }

    public func save(_ preferences: ModelBarPreferences) {
        defaults.set(
            preferences.disabledProviderIDs.sorted(),
            forKey: Keys.disabledProviders
        )
        defaults.set(
            preferences.hiddenAgentIDs.sorted(),
            forKey: Keys.hiddenAgents
        )
        defaults.set(
            preferences.refreshInterval.rawValue,
            forKey: Keys.refreshInterval
        )
    }
}
