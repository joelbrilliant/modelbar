import AppKit
import ModelBarCore

@MainActor
final class ProviderCardView: NSView {
    private static let width: CGFloat = 360
    private static let horizontalPadding: CGFloat = 12
    private let presentationBrand: ProviderBrand?

    init(presentation: ProviderCardPresentation) {
        presentationBrand = presentation.brand
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 1))
        wantsLayer = true
        layer?.cornerRadius = 8

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let accent = ProviderAccentView(brand: presentation.brand)
        accent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accent)

        let contentWidth = Self.width - (Self.horizontalPadding * 2)
        let headerRow = header(
            title: presentation.displayName,
            status: presentation.statusText,
            condition: presentation.statusCondition,
            brand: presentation.brand
        )
        content.addArrangedSubview(headerRow)
        content.setCustomSpacing(6, after: headerRow)

        // Freshness is only worth a line when it is a problem.
        if presentation.isStale {
            let age = label(
                presentation.ageText,
                font: .systemFont(ofSize: 10),
                colour: .secondaryLabelColor
            )
            content.addArrangedSubview(age)
            content.setCustomSpacing(6, after: age)
        }

        if presentation.quotaBars.isEmpty {
            content.addArrangedSubview(
                label(
                    "Quota unavailable",
                    font: .systemFont(ofSize: 11),
                    colour: .secondaryLabelColor
                )
            )
        } else {
            for quota in presentation.quotaBars {
                content.addArrangedSubview(
                    QuotaRowView(
                        presentation: quota,
                        brand: presentation.brand,
                        isStale: presentation.isStale
                    )
                )
            }
        }

        if let tokensText = presentation.tokensText {
            let tokens = label(
                tokensText,
                font: .systemFont(ofSize: 11),
                colour: .secondaryLabelColor
            )
            tokens.lineBreakMode = .byTruncatingTail
            tokens.toolTip = tokensText
            content.addArrangedSubview(tokens)
        }

        if let issueText = presentation.issueText {
            content.addArrangedSubview(issueLine(issueText))
        }

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            content.widthAnchor.constraint(equalToConstant: contentWidth),
            accent.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            accent.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            accent.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            accent.widthAnchor.constraint(equalToConstant: 3),
        ])

        layoutSubtreeIfNeeded()
        let height = ceil(content.fittingSize.height) + 18
        frame.size = NSSize(width: Self.width, height: height)
        setAccessibilityElement(true)
        // The age is only part of the label when it is a stale warning, so
        // the label never claims an "Updated" freshness the data lacks.
        var accessibilityParts = [presentation.displayName, presentation.statusText]
        if presentation.isStale {
            accessibilityParts.append(presentation.ageText)
        }
        setAccessibilityLabel(accessibilityParts.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let accent = ProviderBrandStyle.colour(for: presentationBrand)
        let base = NSColor.controlBackgroundColor
        layer?.backgroundColor = (base.blended(withFraction: 0.07, of: accent) ?? base)
            .withAlphaComponent(0.72)
            .cgColor
    }

    private func header(
        title: String,
        status: String,
        condition: ServiceCondition,
        brand: ProviderBrand?
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5

        let titleLabel = label(
            title,
            font: .systemFont(ofSize: 13, weight: .semibold),
            colour: ProviderBrandStyle.colour(for: brand)
        )
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let statusIcon = NSImageView(
            image: NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        statusIcon.contentTintColor = colour(for: condition)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusIcon.widthAnchor.constraint(equalToConstant: 7),
            statusIcon.heightAnchor.constraint(equalToConstant: 7),
        ])
        row.addArrangedSubview(statusIcon)

        let statusLabel = label(
            status,
            font: .systemFont(ofSize: 10, weight: .medium),
            colour: .secondaryLabelColor
        )
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.toolTip = status
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(statusLabel)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 336).isActive = true
        return row
    }

    private func issueLine(_ text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let icon = NSImageView(
            image: NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(symbolConfiguration) ?? NSImage()
        )
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])
        row.addArrangedSubview(icon)

        let message = NSTextField(wrappingLabelWithString: text)
        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 2
        message.lineBreakMode = .byWordWrapping
        message.cell?.truncatesLastVisibleLine = true
        message.preferredMaxLayoutWidth = Self.width - (Self.horizontalPadding * 2) - 18
        message.toolTip = text
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(message)

        row.widthAnchor.constraint(
            equalToConstant: Self.width - (Self.horizontalPadding * 2)
        ).isActive = true
        return row
    }

    private func label(
        _ text: String,
        font: NSFont,
        colour: NSColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = colour
        return field
    }

    private func colour(for condition: ServiceCondition) -> NSColor {
        switch condition {
        case .operational:
            return .systemGreen
        case .degraded:
            return .systemOrange
        case .outage:
            return .systemRed
        case .unknown:
            return .secondaryLabelColor
        }
    }
}

@MainActor
private final class ProviderAccentView: NSView {
    private let brand: ProviderBrand?

    init(brand: ProviderBrand?) {
        self.brand = brand
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ProviderBrandStyle.colour(for: brand).setFill()
        NSBezierPath(
            roundedRect: bounds,
            xRadius: bounds.width / 2,
            yRadius: bounds.width / 2
        ).fill()
    }
}

/// One quota window on one line: name, bar, "N% left" and reset countdown.
/// The name, percentage and countdown sit in fixed columns so they line up
/// across every row in the card.
@MainActor
private final class QuotaRowView: NSView {
    private static let width: CGFloat = 336
    private static let height: CGFloat = 18
    private static let columnGap: CGFloat = 8
    private static let nameColumnWidth: CGFloat = 84
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let leftColumnWidth = columnWidth(for: "100% left")
    private static let countdownColumnWidth = columnWidth(for: "23h 59m")

    init(presentation: QuotaBarPresentation, brand: ProviderBrand?, isStale: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Self.columnGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let textColour: NSColor = isStale ? .secondaryLabelColor : .labelColor
        let name = Self.column(
            presentation.name,
            font: .systemFont(ofSize: 11),
            colour: textColour,
            width: Self.nameColumnWidth,
            alignment: .left
        )
        name.toolTip = presentation.name
        stack.addArrangedSubview(name)

        let bar = QuotaTrackView(
            fraction: presentation.remainingFraction,
            capacityState: presentation.capacityState,
            brand: brand,
            isStale: isStale
        )
        stack.addArrangedSubview(bar)

        stack.addArrangedSubview(Self.column(
            presentation.leftText,
            font: Self.numberFont,
            colour: textColour,
            width: Self.leftColumnWidth,
            alignment: .right
        ))
        stack.addArrangedSubview(Self.column(
            presentation.countdownText,
            font: Self.numberFont,
            colour: .secondaryLabelColor,
            width: Self.countdownColumnWidth,
            alignment: .right
        ))

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            heightAnchor.constraint(equalToConstant: Self.height),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // The row reads as one element so VoiceOver speaks the window, the
        // percentage and the reset together instead of four fragments.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(presentation.accessibilityText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private static func columnWidth(for sample: String) -> CGFloat {
        ceil(NSAttributedString(
            string: sample,
            attributes: [.font: numberFont]
        ).size().width) + 1
    }

    private static func column(
        _ text: String,
        font: NSFont,
        colour: NSColor,
        width: CGFloat,
        alignment: NSTextAlignment
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = colour
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.setAccessibilityElement(false)
        return field
    }
}

@MainActor
private final class QuotaTrackView: NSView {
    private static let height: CGFloat = 6
    private static let staleFillAlpha: CGFloat = 0.4

    private let fraction: CGFloat
    private let capacityState: QuotaCapacityState
    private let brand: ProviderBrand?
    private let isStale: Bool

    init(
        fraction: Double,
        capacityState: QuotaCapacityState,
        brand: ProviderBrand?,
        isStale: Bool
    ) {
        self.fraction = CGFloat(min(1, max(0, fraction)))
        self.capacityState = capacityState
        self.brand = brand
        self.isStale = isStale
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: Self.height))
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let radius = bounds.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else {
            return
        }
        let fillRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.height, bounds.width * fraction),
            height: bounds.height
        )
        var fill = ProviderBrandStyle.capacityColour(for: capacityState, brand: brand)
        if isStale {
            fill = fill.withAlphaComponent(Self.staleFillAlpha)
        }
        fill.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}

@MainActor
final class AgentTokenRowView: NSView {
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = title
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
