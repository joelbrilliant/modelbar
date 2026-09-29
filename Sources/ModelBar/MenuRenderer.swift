import AppKit
import ModelBarCore

@MainActor
final class MenuRenderer {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private weak var refreshItem: NSMenuItem?
    private var isRefreshing = false
    private var displayedStatusSegments: [StatusSegmentPresentation]?

    init(statusItem: NSStatusItem, menu: NSMenu) {
        self.statusItem = statusItem
        self.menu = menu
    }

    func renderLoading(
        refreshTarget: AnyObject,
        refreshAction: Selector,
        settingsTarget: AnyObject,
        settingsAction: Selector,
        quitTarget: AnyObject,
        quitAction: Selector
    ) {
        configureSymbolStatusButton(
            title: "…",
            accessibilityLabel: "Model usage loading",
            toolTip: nil
        )
        menu.removeAllItems()
        menu.addItem(sectionHeader("ModelBar"))
        menu.addItem(readOnlyItem("Loading usage…"))
        addActions(
            refreshTarget: refreshTarget,
            refreshAction: refreshAction,
            settingsTarget: settingsTarget,
            settingsAction: settingsAction,
            quitTarget: quitTarget,
            quitAction: quitAction
        )
    }

    func renderCompact(
        _ snapshot: ModelBarSnapshot,
        preferences: ModelBarPreferences,
        refreshTarget: AnyObject,
        refreshAction: Selector,
        settingsTarget: AnyObject,
        settingsAction: Selector,
        quitTarget: AnyObject,
        quitAction: Selector
    ) {
        let presentation = MenuPresentationBuilder.build(
            snapshot: snapshot,
            preferences: preferences
        )
        configureStatusButton(presentation)

        menu.removeAllItems()
        menu.addItem(readOnlyItem("Open ModelBar to view usage"))
        menu.addItem(readOnlyItem(presentation.footer))
        addActions(
            refreshTarget: refreshTarget,
            refreshAction: refreshAction,
            settingsTarget: settingsTarget,
            settingsAction: settingsAction,
            quitTarget: quitTarget,
            quitAction: quitAction
        )
    }

    func renderVisual(
        _ snapshot: ModelBarSnapshot,
        preferences: ModelBarPreferences,
        refreshTarget: AnyObject,
        refreshAction: Selector,
        settingsTarget: AnyObject,
        settingsAction: Selector,
        quitTarget: AnyObject,
        quitAction: Selector
    ) {
        let presentation = MenuPresentationBuilder.build(
            snapshot: snapshot,
            preferences: preferences
        )
        configureStatusButton(presentation)

        menu.removeAllItems()
        menu.addItem(sectionHeader("Providers"))
        if presentation.providerCards.isEmpty {
            menu.addItem(readOnlyItem(MenuPresentationBuilder.waitingForProviderDataText))
        } else {
            for card in presentation.providerCards {
                menu.addItem(providerCardItem(card))
            }
        }

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Hermes agents"))
        for row in presentation.agentRows {
            menu.addItem(agentRowItem(row))
        }

        menu.addItem(.separator())
        menu.addItem(readOnlyItem(presentation.footer))
        addActions(
            refreshTarget: refreshTarget,
            refreshAction: refreshAction,
            settingsTarget: settingsTarget,
            settingsAction: settingsAction,
            quitTarget: quitTarget,
            quitAction: quitAction
        )
    }

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        refreshItem?.title = refreshing ? "Refreshing…" : "Refresh now"
        refreshItem?.isEnabled = !refreshing
    }

    private func addActions(
        refreshTarget: AnyObject,
        refreshAction: Selector,
        settingsTarget: AnyObject,
        settingsAction: Selector,
        quitTarget: AnyObject,
        quitAction: Selector
    ) {
        menu.addItem(.separator())
        let refresh = NSMenuItem(
            title: "Refresh now",
            action: refreshAction,
            keyEquivalent: "r"
        )
        refresh.target = refreshTarget
        refresh.title = isRefreshing ? "Refreshing…" : "Refresh now"
        refresh.isEnabled = !isRefreshing
        menu.addItem(refresh)
        refreshItem = refresh

        let settings = NSMenuItem(
            title: "Settings…",
            action: settingsAction,
            keyEquivalent: ","
        )
        settings.target = settingsTarget
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit ModelBar",
            action: quitAction,
            keyEquivalent: "q"
        )
        quit.target = quitTarget
        menu.addItem(quit)
    }

    private func configureStatusButton(_ presentation: MenuPresentation) {
        guard !presentation.statusSegments.isEmpty else {
            configureSymbolStatusButton(
                title: presentation.statusTitle,
                accessibilityLabel: presentation.accessibilityLabel,
                toolTip: presentation.statusToolTip
            )
            return
        }
        guard let button = statusItem.button else {
            return
        }
        if displayedStatusSegments != presentation.statusSegments {
            button.image = StatusItemImage.make(
                segments: presentation.statusSegments,
                appearanceSource: button
            )
            button.imagePosition = .imageOnly
            button.title = ""
            displayedStatusSegments = presentation.statusSegments
        }
        button.toolTip = presentation.statusToolTip
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func configureSymbolStatusButton(
        title: String,
        accessibilityLabel: String,
        toolTip: String?
    ) {
        guard let button = statusItem.button else {
            return
        }
        button.image = NSImage(
            systemSymbolName: "chart.bar.fill",
            accessibilityDescription: "Model usage"
        )
        button.imagePosition = .imageLeading
        button.title = " \(title)"
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)
        displayedStatusSegments = nil
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func readOnlyItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func readOnlyItem(_ row: MenuPresentationRow) -> NSMenuItem {
        let item = readOnlyItem(row.title)
        item.indentationLevel = row.indentationLevel
        return item
    }

    private func providerCardItem(_ presentation: ProviderCardPresentation) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = ProviderCardView(presentation: presentation)
        return item
    }

    private func agentRowItem(_ row: MenuPresentationRow) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = AgentTokenRowView(title: row.title)
        return item
    }
}
