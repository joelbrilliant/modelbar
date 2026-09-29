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
        "\(percentNumber(value))%"
    }

    /// Whole-number percentage without a percent sign. `percent` appends
    /// the sign to this value so every surface rounds identically.
    public static func percentNumber(_ value: Double) -> String {
        String(format: "%.0f", min(100, max(0, value)))
    }

    /// Time left until `date` as a compact figure for one-line quota rows:
    /// "42m", "3h 44m", "3d 13h". Whole units are floored, so it never
    /// promises more time than remains.
    public static func countdown(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return unavailableCountdown
        }
        if date <= now {
            return "due"
        }
        let seconds = Int(date.timeIntervalSince(now))
        let minutes = seconds / 60
        if seconds < 3_600 {
            return "\(max(1, minutes))m"
        }
        let hours = seconds / 3_600
        if seconds < 86_400 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(hours / 24)d \(hours % 24)h"
    }

    public static let unavailableCountdown = "\u{2013}"

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

    /// Reset time as an absolute clock time, for text that can sit on screen
    /// long after it was built (the status item tooltip). Unlike `reset`,
    /// it stays true however much later it is read.
    public static func resetClock(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else {
            return "reset unknown"
        }
        if date <= now {
            return "reset due"
        }
        return "resets \(clockTime(date, now: now, calendar: calendar))"
    }

    /// Absolute time of day, with a weekday when `date` is on another
    /// calendar day within the next week and a day and month beyond that.
    public static func clockTime(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        let template: String
        switch days {
        case 0:
            template = "jmm"
        case 1...6:
            template = "EEEjmm"
        default:
            template = "dMMMjmm"
        }
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
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
