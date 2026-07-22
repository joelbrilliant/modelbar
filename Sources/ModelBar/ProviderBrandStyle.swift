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
}
