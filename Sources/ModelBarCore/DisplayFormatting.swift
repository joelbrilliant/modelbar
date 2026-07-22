import Foundation

public enum DisplayFormatting {
    public static func tokens(_ value: Int64) -> String {
        let number = Double(max(0, value))
        let divisor: Double
        let suffix: String
        switch number {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return String(Int64(number))
        }

        let scaled = number / divisor
        let formatted = scaled >= 100
            ? String(format: "%.0f", scaled)
            : String(format: "%.1f", scaled)
        return formatted.replacingOccurrences(of: ".0", with: "") + suffix
    }

    public static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(100, max(0, value)))
    }

    public static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "reset unknown"
        }
        if date <= now {
            return "reset due"
        }
        let seconds = date.timeIntervalSince(now)
        if seconds < 3_600 {
            return "resets in \(max(1, Int(ceil(seconds / 60))))m"
        }
        if seconds < 86_400 {
            return "resets in \(max(1, Int(ceil(seconds / 3_600))))h"
        }
        return "resets in \(max(1, Int(ceil(seconds / 86_400))))d"
    }

    public static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        }
        return "\(Int(seconds / 3_600))h ago"
    }
}
