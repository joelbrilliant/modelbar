import AppKit
import ModelBarCore

/// Composes the closed status item: one vertical gauge plus a bare
/// percentage-left figure per enabled provider.
///
/// The result is a single non-template image whose drawing handler runs every
/// time AppKit draws the button (`cacheMode = .never`). Dynamic colours are
/// resolved inside the handler against the button's effective appearance, so
/// light, dark and runtime appearance switches render correctly without a
/// data refresh, a timer or an appearance observer.
@MainActor
enum StatusItemImage {
    private static let gaugeWidth: CGFloat = 4
    private static let gaugeHeight: CGFloat = 12
    private static let gaugeToValueGap: CGFloat = 3
    private static let segmentGap: CGFloat = 7
    private static let staleFillAlpha: CGFloat = 0.4

    static var font: NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
            weight: .regular
        )
    }

    static func make(
        segments: [StatusSegmentPresentation],
        appearanceSource: NSView?
    ) -> NSImage {
        let font = font
        func textWidth(_ text: String) -> CGFloat {
            ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
        }
        // Every value gets at least a two-digit slot, so dropping to one digit
        // or the unavailable placeholder keeps the item's width. Only an
        // untouched quota ("100") widens its segment, which avoids reserving
        // three digits of menu bar space for a value that is rarely shown.
        let slotWidth = max(
            textWidth("88"),
            textWidth(StatusSegmentPresentation.unavailableText)
        )
        let valueWidths = segments.map { max(slotWidth, textWidth($0.valueText)) }
        let contentWidth = valueWidths.reduce(0) { total, valueWidth in
            total + gaugeWidth + gaugeToValueGap + valueWidth
        } + segmentGap * CGFloat(max(0, segments.count - 1))
        let size = NSSize(
            width: ceil(contentWidth),
            height: NSStatusBar.system.thickness
        )

        let image = NSImage(size: size, flipped: false) { [weak appearanceSource] bounds in
            let drawSegments = {
                draw(
                    segments: segments,
                    valueWidths: valueWidths,
                    font: font,
                    in: bounds
                )
            }
            if let appearance = appearanceSource?.effectiveAppearance {
                appearance.performAsCurrentDrawingAppearance(drawSegments)
            } else {
                drawSegments()
            }
            return true
        }
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }

    private static func draw(
        segments: [StatusSegmentPresentation],
        valueWidths: [CGFloat],
        font: NSFont,
        in bounds: NSRect
    ) {
        let scale = backingScale()
        func align(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }

        let gaugeY = align((bounds.height - gaugeHeight) / 2)
        // Rounded up to a whole point at every scale, which matches the
        // baseline NSStatusBarButtonCell uses for native titles.
        let baselineY = ceil((bounds.height - font.capHeight) / 2)
        var x: CGFloat = 0

        for (segment, valueWidth) in zip(segments, valueWidths) {
            let gauge = NSRect(
                x: align(x),
                y: gaugeY,
                width: gaugeWidth,
                height: gaugeHeight
            )
            drawGauge(segment: segment, in: gauge, align: align)

            // Figures stay in the menu bar text colour at every capacity
            // level so they read without relying on red or orange. Low and
            // critical are carried by the gauge, tooltip and VoiceOver label.
            let valueColour: NSColor = segment.isStale || segment.remainingFraction == nil
                ? .secondaryLabelColor
                : .labelColor
            NSAttributedString(
                string: segment.valueText,
                attributes: [
                    .font: font,
                    .foregroundColor: valueColour,
                ]
            ).draw(at: NSPoint(
                x: align(x + gaugeWidth + gaugeToValueGap),
                y: baselineY + font.descender
            ))

            x += gaugeWidth + gaugeToValueGap + valueWidth + segmentGap
        }
    }

    private static func drawGauge(
        segment: StatusSegmentPresentation,
        in rect: NSRect,
        align: (CGFloat) -> CGFloat
    ) {
        let radius = rect.width / 2
        let track = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.tertiaryLabelColor.setFill()
        track.fill()

        guard let fraction = segment.remainingFraction, fraction > 0 else {
            return
        }
        let clamped = min(1, max(0, fraction))
        // At least a full rounded cap, as the card bars do, so low and
        // critical colours stay visible.
        let fillHeight = max(rect.width, align(rect.height * clamped))
        var fill = segment.capacityState.map {
            ProviderBrandStyle.capacityColour(for: $0, brand: segment.brand)
        } ?? ProviderBrandStyle.colour(for: segment.brand)
        if segment.isStale {
            fill = fill.withAlphaComponent(staleFillAlpha)
        }

        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        fill.setFill()
        NSRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: fillHeight
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func backingScale() -> CGFloat {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return 2
        }
        let transform = context.userSpaceToDeviceSpaceTransform
        let scale = hypot(transform.a, transform.b)
        return scale >= 1 ? scale : 1
    }
}
