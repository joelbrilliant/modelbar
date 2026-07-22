import AppKit
import ModelBarCore
import ServiceManagement

struct SettingsOption: Equatable {
    let id: String
    let displayName: String
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onApply: (ModelBarPreferences) -> Void
    private var providerButtons: [String: NSButton] = [:]
    private var agentButtons: [String: NSButton] = [:]
    private var refreshPopUp: NSPopUpButton?
    private var launchAtLoginButton: NSButton?
    private var errorLabel: NSTextField?
    private var basePreferences = ModelBarPreferences()

    init(onApply: @escaping (ModelBarPreferences) -> Void) {
        self.onApply = onApply
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present(
        preferences: ModelBarPreferences,
        providerOptions: [SettingsOption],
        agentOptions: [SettingsOption]
    ) {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = makeWindow(
            preferences: preferences,
            providerOptions: providerOptions,
            agentOptions: agentOptions
        )
        self.window = window
        window.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(
        preferences: ModelBarPreferences,
        providerOptions: [SettingsOption],
        agentOptions: [SettingsOption]
    ) -> NSWindow {
        providerButtons.removeAll()
        agentButtons.removeAll()
        basePreferences = preferences

        let content = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.addArrangedSubview(sectionTitle("Providers"))
        for option in providerOptions {
            let button = NSButton(
                checkboxWithTitle: option.displayName,
                target: nil,
                action: nil
            )
            button.state = preferences.isProviderEnabled(option.id) ? .on : .off
            button.setAccessibilityLabel("Show and refresh \(option.displayName)")
            providerButtons[option.id] = button
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Hermes profiles"))
        if agentOptions.isEmpty {
            let empty = NSTextField(labelWithString: "No profiles discovered yet")
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        } else {
            for option in agentOptions {
                let button = NSButton(
                    checkboxWithTitle: option.displayName,
                    target: nil,
                    action: nil
                )
                button.state = preferences.isAgentVisible(option.id) ? .on : .off
                button.setAccessibilityLabel("Show Hermes profile \(option.displayName)")
                agentButtons[option.id] = button
                stack.addArrangedSubview(button)
            }
        }

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("Refresh"))
        let refreshRow = NSStackView()
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.spacing = 12
        let refreshLabel = NSTextField(labelWithString: "Background refresh")
        refreshLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        refreshRow.addArrangedSubview(refreshLabel)

        let refreshPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        self.refreshPopUp = refreshPopUp
        for interval in RefreshInterval.allCases {
            refreshPopUp.addItem(withTitle: interval.title)
            refreshPopUp.lastItem?.representedObject = interval.rawValue
        }
        select(interval: preferences.refreshInterval)
        refreshPopUp.setAccessibilityLabel("Background refresh interval")
        refreshRow.addArrangedSubview(refreshPopUp)
        stack.addArrangedSubview(refreshRow)

        let launchAtLoginButton = NSButton(
            checkboxWithTitle: "Launch ModelBar at login",
            target: nil,
            action: nil
        )
        self.launchAtLoginButton = launchAtLoginButton
        let launchState = currentLaunchState()
        launchAtLoginButton.state = launchState.registered ? .on : .off
        launchAtLoginButton.isEnabled = launchState.canChange
        stack.addArrangedSubview(launchAtLoginButton)

        let launchStatus = NSTextField(labelWithString: launchState.description)
        launchStatus.font = .systemFont(ofSize: 11)
        launchStatus.textColor = .secondaryLabelColor
        launchStatus.maximumNumberOfLines = 2
        stack.addArrangedSubview(launchStatus)

        let errorLabel = NSTextField(labelWithString: "")
        self.errorLabel = errorLabel
        errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        buttons.addArrangedSubview(cancel)

        let apply = NSButton(title: "Apply", target: self, action: #selector(apply))
        apply.keyEquivalent = "\r"
        apply.bezelStyle = .rounded
        buttons.addArrangedSubview(apply)
        stack.addArrangedSubview(buttons)

        let contentWidth: CGFloat = 400
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
            refreshRow.widthAnchor.constraint(equalToConstant: contentWidth),
            buttons.widthAnchor.constraint(equalToConstant: contentWidth),
        ])

        content.layoutSubtreeIfNeeded()
        let height = max(360, ceil(stack.fittingSize.height) + 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth + 40, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ModelBar Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        return window
    }

    @objc private func apply() {
        guard let launchAtLoginButton, let refreshPopUp else {
            return
        }
        let enabledProviders = providerButtons
            .filter { $0.value.state == .on }
            .map(\.key)
        guard !enabledProviders.isEmpty else {
            showError("Keep at least one provider enabled.")
            NSSound.beep()
            return
        }

        do {
            try updateLaunchAtLogin(enabled: launchAtLoginButton.state == .on)
        } catch {
            showError("Launch at login could not be changed: \(error.localizedDescription)")
            return
        }

        var disabledProviderIDs = basePreferences.disabledProviderIDs
        for (id, button) in providerButtons {
            if button.state == .on {
                disabledProviderIDs.remove(id)
            } else {
                disabledProviderIDs.insert(id)
            }
        }
        var hiddenAgentIDs = basePreferences.hiddenAgentIDs
        for (id, button) in agentButtons {
            if button.state == .on {
                hiddenAgentIDs.remove(id)
            } else {
                hiddenAgentIDs.insert(id)
            }
        }
        let intervalRaw = refreshPopUp.selectedItem?.representedObject as? Int
        let interval = intervalRaw.flatMap(RefreshInterval.init(rawValue:))
            ?? .fifteenMinutes
        onApply(
            ModelBarPreferences(
                disabledProviderIDs: disabledProviderIDs,
                hiddenAgentIDs: hiddenAgentIDs,
                refreshInterval: interval
            )
        )
        dismissWindow()
    }

    @objc private func cancel() {
        dismissWindow()
    }

    private func select(interval: RefreshInterval) {
        let index = RefreshInterval.allCases.firstIndex(of: interval) ?? 1
        refreshPopUp?.selectItem(at: index)
    }

    private func showError(_ message: String) {
        errorLabel?.stringValue = message
        errorLabel?.isHidden = false
        window?.recalculateKeyViewLoop()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        releaseViewReferences()
    }

    private func dismissWindow() {
        let activeWindow = window
        activeWindow?.delegate = nil
        activeWindow?.close()
        window = nil
        releaseViewReferences()
    }

    private func releaseViewReferences() {
        providerButtons.removeAll()
        agentButtons.removeAll()
        refreshPopUp = nil
        launchAtLoginButton = nil
        errorLabel = nil
    }

    private func updateLaunchAtLogin(enabled: Bool) throws {
        let service = SMAppService.mainApp
        let registered = service.status == .enabled || service.status == .requiresApproval
        guard enabled != registered else {
            return
        }
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    private func currentLaunchState() -> (
        registered: Bool,
        description: String,
        canChange: Bool
    ) {
        switch SMAppService.mainApp.status {
        case .enabled:
            return (true, "Enabled in macOS Login Items", true)
        case .requiresApproval:
            return (true, "Approval is required in System Settings > Login Items", true)
        case .notRegistered:
            return (false, "Disabled", true)
        case .notFound:
            return (
                false,
                "macOS could not find a login service for this local build",
                false
            )
        @unknown default:
            return (false, "Status unavailable", false)
        }
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 400).isActive = true
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }
}
