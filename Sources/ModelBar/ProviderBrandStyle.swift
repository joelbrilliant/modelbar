import AppKit
import ModelBarCore

@MainActor
enum ProviderBrandStyle {
    static func colour(for brand: ProviderBrand?) -> NSColor {
        guard let brand else {
            return .secondaryLabelColor
        }
        return NSColor(name: nil) { appearance in
            let colour = switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                brand.darkModeAccent
            default:
                brand.lightModeAccent
            }
            return NSColor(
                red: CGFloat(colour.red) / 255,
                green: CGFloat(colour.green) / 255,
                blue: CGFloat(colour.blue) / 255,
                alpha: 1
            )
        }
    }

    /// Fill colour for remaining capacity, shared by menu cards and the
    /// status item so low and critical always look the same.
    static func capacityColour(
        for state: QuotaCapacityState,
        brand: ProviderBrand?
    ) -> NSColor {
        switch state {
        case .healthy:
            return colour(for: brand)
        case .low:
            return .systemOrange
        case .critical:
            return .systemRed
        }
    }
}
