import AppKit
import Foundation
import ModelBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let providerRegistry: ProviderRegistry
    private let refreshCoordinator: RefreshCoordinator
    private let snapshotStore: SnapshotStore
    private let renderer: MenuRenderer
    private let preferencesStore: PreferencesStore
    private let providerOptions: [SettingsOption]

    private var snapshot: ModelBarSnapshot?
    private var preferences: ModelBarPreferences
    private var refreshTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var refreshRequested = false
    private var menuIsOpen = false

    private lazy var settingsWindowController = SettingsWindowController {
        [weak self] preferences in
        self?.apply(preferences: preferences)
    }

    override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexBar = Self.codexBarExecutable()
        let registry = ProviderRegistry.standard(
            codexBarExecutable: codexBar,
            homeDirectory: home
        )
        providerRegistry = registry
        providerOptions = registry.providers.map {
            SettingsOption(id: $0.id, displayName: $0.displayName)
        }
        let hermes = HermesTokenReader(
            hermesHome: home.appendingPathComponent(".hermes")
        )
        refreshCoordinator = RefreshCoordinator(
            service: RefreshService(
                registry: registry,
                runner: ProcessCommandRunner(),
                agentSource: hermes
            )
        )

        let cacheURL = home
            .appendingPathComponent("Library/Application Support/ModelBar")
            .appendingPathComponent("snapshot.json")
        snapshotStore = SnapshotStore(fileURL: cacheURL)
        renderer = MenuRenderer(statusItem: statusItem, menu: menu)
        preferencesStore = PreferencesStore()
        preferences = preferencesStore.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        renderer.renderLoading(
            refreshTarget: self,
            refreshAction: #selector(refreshNow),
            settingsTarget: self,
            settingsAction: #selector(showSettings),
            quitTarget: self,
            quitAction: #selector(quit)
        )

        ensureAtLeastOneProviderIsEnabled()
        configureRefreshTimer()

        Task {
            if var cached = await snapshotStore.load() {
                cached = providerRegistry.applyingRegisteredMetadata(to: cached)
                for index in cached.providers.indices {
                    cached.providers[index].isStale = true
                }
                for index in cached.agents.indices {
                    cached.agents[index].isStale = true
                }
                snapshot = cached
                render(cached)
            }
            refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        refreshTimer?.invalidate()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showSettings()
        }
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        guard let snapshot else {
            renderer.renderLoading(
                refreshTarget: self,
                refreshAction: #selector(refreshNow),
                settingsTarget: self,
                settingsAction: #selector(showSettings),
                quitTarget: self,
                quitAction: #selector(quit)
            )
            refresh()
            return
        }
        render(snapshot)
        if Date().timeIntervalSince(snapshot.refreshedAt) > 120 {
            refresh()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        Task { @MainActor [weak self] in
            guard let self, !menuIsOpen, let snapshot else {
                return
            }
            render(snapshot)
        }
    }

    @objc private func timerFired() {
        refresh()
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func showSettings() {
        let agents = snapshot?.agents.map {
            SettingsOption(id: $0.id, displayName: $0.displayName)
        } ?? []
        settingsWindowController.present(
            preferences: preferences,
            providerOptions: providerOptions,
            agentOptions: agents
        )
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh(queueIfBusy: Bool = false) {
        guard refreshTask == nil else {
            if queueIfBusy {
                refreshRequested = true
            }
            return
        }
        renderer.setRefreshing(true)
        let previous = snapshot
        let enabledProviderIDs = Set(
            providerOptions
                .filter { preferences.isProviderEnabled($0.id) }
                .map(\.id)
        )

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            let fresh = await refreshCoordinator.refresh(
                enabledProviderIDs: enabledProviderIDs
            )
            guard !Task.isCancelled else {
                renderer.setRefreshing(false)
                refreshTask = nil
                return
            }
            let merged = SnapshotMerger.merge(fresh: fresh, previous: previous)
            snapshot = merged
            renderer.setRefreshing(false)
            render(merged)
            _ = try? await snapshotStore.saveIfDisplayChanged(merged)
            refreshTask = nil
            if refreshRequested {
                refreshRequested = false
                refresh()
            }
        }
    }

    private func render(_ snapshot: ModelBarSnapshot) {
        if menuIsOpen {
            renderer.renderVisual(
                snapshot,
                preferences: preferences,
                refreshTarget: self,
                refreshAction: #selector(refreshNow),
                settingsTarget: self,
                settingsAction: #selector(showSettings),
                quitTarget: self,
                quitAction: #selector(quit)
            )
        } else {
            renderer.renderCompact(
                snapshot,
                preferences: preferences,
                refreshTarget: self,
                refreshAction: #selector(refreshNow),
                settingsTarget: self,
                settingsAction: #selector(showSettings),
                quitTarget: self,
                quitAction: #selector(quit)
            )
        }
    }

    private func apply(preferences: ModelBarPreferences) {
        self.preferences = preferences
        preferencesStore.save(preferences)
        configureRefreshTimer()
        if let snapshot {
            render(snapshot)
        }
        refresh(queueIfBusy: true)
    }

    private func configureRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard let interval = preferences.refreshInterval.seconds else {
            return
        }
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func ensureAtLeastOneProviderIsEnabled() {
        guard let first = providerOptions.first,
              providerOptions.allSatisfy({ !preferences.isProviderEnabled($0.id) }) else {
            return
        }
        preferences.disabledProviderIDs.remove(first.id)
        preferencesStore.save(preferences)
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ModelBar")

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit ModelBar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private static func codexBarExecutable() -> URL {
        let candidates = [
            "/opt/homebrew/bin/codexbar",
            "/usr/local/bin/codexbar",
        ]
        let path = candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? candidates[0]
        return URL(fileURLWithPath: path)
    }
}
