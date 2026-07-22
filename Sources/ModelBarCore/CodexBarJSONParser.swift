import Foundation

public struct ParsedQuota: Sendable {
    public let windows: [QuotaWindow]
    public let status: ServiceStatus?

    public init(windows: [QuotaWindow], status: ServiceStatus?) {
        self.windows = windows
        self.status = status
    }
}

public enum CodexBarParseError: Error {
    case invalidRoot
    case missingUsage
    case missingQuotaWindows
    case missingTokenTotals
}

public enum CodexBarJSONParser {
    public static func parseQuota(
        _ data: Data,
        primaryName: String,
        secondaryName: String
    ) throws -> ParsedQuota {
        let root = try rootObject(from: data)
        guard let usage = root["usage"] as? [String: Any] else {
            throw CodexBarParseError.missingUsage
        }

        var windows: [QuotaWindow] = []
        if let primary = usage["primary"] as? [String: Any],
           let window = parseWindow(primary, name: primaryName) {
            windows.append(window)
        }
        if let secondary = usage["secondary"] as? [String: Any],
           let window = parseWindow(secondary, name: secondaryName) {
            windows.append(window)
        }
        if let extras = usage["extraRateWindows"] as? [[String: Any]] {
            for extra in extras {
                guard let title = extra["title"] as? String,
                      let value = extra["window"] as? [String: Any],
                      let window = parseWindow(value, name: title) else {
                    continue
                }
                windows.append(window)
            }
        }

        guard !windows.isEmpty else {
            throw CodexBarParseError.missingQuotaWindows
        }

        let status = parseStatus(root["status"] as? [String: Any])
        return ParsedQuota(windows: windows, status: status)
    }

    public static func parseTokens(_ data: Data) throws -> TokenUsage {
        let root = try rootObject(from: data)
        guard let recent = integer(root["sessionTokens"]),
              let totals = root["totals"] as? [String: Any],
              let sevenDays = integer(totals["totalTokens"]) else {
            throw CodexBarParseError.missingTokenTotals
        }
        return TokenUsage(
            recentTokens: recent,
            sevenDayTokens: sevenDays,
            recentLabel: "today",
            qualifier: "local"
        )
    }

    private static func rootObject(from data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw CodexBarParseError.invalidRoot
        }
        guard let array = value as? [[String: Any]], let root = array.first else {
            throw CodexBarParseError.invalidRoot
        }
        return root
    }

    private static func parseWindow(
        _ object: [String: Any],
        name: String
    ) -> QuotaWindow? {
        guard let used = number(object["usedPercent"]) else {
            return nil
        }
        return QuotaWindow(
            name: name,
            usedPercent: used,
            resetsAt: date(object["resetsAt"])
        )
    }

    private static func parseStatus(_ object: [String: Any]?) -> ServiceStatus? {
        guard let object,
              let description = object["description"] as? String else {
            return nil
        }
        let indicator = (object["indicator"] as? String)?.lowercased() ?? "unknown"
        let condition: ServiceCondition
        switch indicator {
        case "none":
            condition = .operational
        case "minor", "maintenance":
            condition = .degraded
        case "major", "critical":
            condition = .outage
        default:
            condition = .unknown
        }
        return ServiceStatus(
            condition: condition,
            description: description,
            url: (object["url"] as? String).flatMap(URL.init(string:))
        )
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else {
            return nil
        }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }
}
