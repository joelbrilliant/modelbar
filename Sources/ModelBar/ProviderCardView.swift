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
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let accent = ProviderAccentView(brand: presentation.brand)
        accent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accent)

        let contentWidth = Self.width - (Self.horizontalPadding * 2)
        content.addArrangedSubview(
            header(
                title: presentation.displayName,
                status: presentation.statusText,
                condition: presentation.statusCondition,
                brand: presentation.brand
            )
        )
        content.addArrangedSubview(
            label(
                presentation.ageText,
                font: .systemFont(ofSize: 10),
                colour: .secondaryLabelColor
            )
        )
        content.addArrangedSubview(separator())

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
                        brand: presentation.brand
                    )
                )
            }
        }

        if let tokensText = presentation.tokensText {
            content.addArrangedSubview(separator())
            content.addArrangedSubview(
                label(
                    tokensText,
                    font: .systemFont(ofSize: 11),
                    colour: .labelColor
                )
            )
        }

        if let issueText = presentation.issueText {
            let issue = label(
                "⚠ \(issueText)",
                font: .systemFont(ofSize: 11, weight: .medium),
                colour: .systemRed
            )
            issue.maximumNumberOfLines = 2
            issue.lineBreakMode = .byWordWrapping
            content.addArrangedSubview(issue)
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
        frame.size = NSSize(width: Self.width, height: max(80, height))
        setAccessibilityElement(true)
        setAccessibilityLabel(
            "\(presentation.displayName), \(presentation.statusText), \(presentation.ageText)"
        )
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

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 336).isActive = true
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
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

@MainActor
private final class QuotaRowView: NSView {
    private static let width: CGFloat = 336

    init(presentation: QuotaBarPresentation, brand: ProviderBrand?) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 42))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let name = NSTextField(labelWithString: presentation.name)
        name.font = .systemFont(ofSize: 11, weight: .medium)
        stack.addArrangedSubview(name)

        let bar = QuotaTrackView(
            fraction: presentation.remainingFraction,
            capacityState: presentation.capacityState,
            brand: brand
        )
        bar.setAccessibilityLabel(
            "\(presentation.name), \(presentation.leftText), \(presentation.resetText)"
        )
        stack.addArrangedSubview(bar)

        let detail = NSStackView()
        detail.orientation = .horizontal
        detail.alignment = .centerY

        let left = NSTextField(labelWithString: presentation.leftText)
        left.font = .systemFont(ofSize: 10, weight: .medium)
        left.textColor = detailColour(
            for: presentation.capacityState,
            brand: brand
        )
        detail.addArrangedSubview(left)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detail.addArrangedSubview(spacer)

        let reset = NSTextField(labelWithString: presentation.resetText)
        reset.font = .systemFont(ofSize: 10)
        reset.textColor = .secondaryLabelColor
        detail.addArrangedSubview(reset)
        stack.addArrangedSubview(detail)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            bar.widthAnchor.constraint(equalToConstant: Self.width),
            detail.widthAnchor.constraint(equalToConstant: Self.width),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func detailColour(
        for state: QuotaCapacityState,
        brand: ProviderBrand?
    ) -> NSColor {
        switch state {
        case .healthy:
            return ProviderBrandStyle.colour(for: brand)
        case .low:
            return .systemOrange
        case .critical:
            return .systemRed
        }
    }
}

@MainActor
private final class QuotaTrackView: NSView {
    private let fraction: CGFloat
    private let capacityState: QuotaCapacityState
    private let brand: ProviderBrand?

    init(
        fraction: Double,
        capacityState: QuotaCapacityState,
        brand: ProviderBrand?
    ) {
        self.fraction = CGFloat(min(1, max(0, fraction)))
        self.capacityState = capacityState
        self.brand = brand
        super.init(frame: NSRect(x: 0, y: 0, width: 336, height: 7))
        setAccessibilityElement(true)
        setAccessibilityValue("\(Int(round(fraction * 100))) percent remaining")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = bounds.insetBy(dx: 0, dy: 1)
        let radius = track.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard fraction > 0 else {
            return
        }
        let fillRect = NSRect(
            x: track.minX,
            y: track.minY,
            width: max(track.height, track.width * fraction),
            height: track.height
        )
        fillColour.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private var fillColour: NSColor {
        switch capacityState {
        case .healthy:
            return ProviderBrandStyle.colour(for: brand)
        case .low:
            return .systemOrange
        case .critical:
            return .systemRed
        }
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
