import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let viewModel: SleepGuardViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: SleepGuardViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        bindViewModel()
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.stopAutoRefresh()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: viewModel.menuBarSystemImage, accessibilityDescription: "SleepGuard")
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: SleepGuardRootView(viewModel: viewModel)
                .frame(width: 390, height: 560)
        )
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusImage()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusImage() {
        statusItem.button?.image = NSImage(systemSymbolName: viewModel.menuBarSystemImage, accessibilityDescription: "SleepGuard")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        Task { await viewModel.start() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let preventionStatusItem = NSMenuItem(title: viewModel.sleepPreventionStatusText, action: nil, keyEquivalent: "")
        preventionStatusItem.isEnabled = false
        menu.addItem(preventionStatusItem)

        if viewModel.sleepPreventionState.isActive {
            let detailItem = NSMenuItem(title: viewModel.sleepPreventionDetailText, action: nil, keyEquivalent: "")
            detailItem.isEnabled = false
            menu.addItem(detailItem)
        }

        menu.addItem(.separator())
        menu.addItem(modeMenuItem(mode: .display))
        menu.addItem(modeMenuItem(mode: .system))
        menu.addItem(modeMenuItem(mode: .displayAndSystem))

        let stopItem = NSMenuItem(title: L("停止防休眠", "Stop Sleep Prevention"), action: #selector(stopSleepPrevention), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = viewModel.sleepPreventionState.isActive
        menu.addItem(stopItem)

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: L("刷新", "Refresh"), action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = viewModel.isRefreshing == false
        menu.addItem(refreshItem)

        let copyItem = NSMenuItem(title: L("复制诊断报告", "Copy Diagnostic Report"), action: #selector(copyReport), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let settingsItem = NSMenuItem(title: L("设置", "Settings"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L("退出 SleepGuard", "Quit SleepGuard"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.popUpMenu(menu)
    }

    private func modeMenuItem(mode: SleepPreventionMode) -> NSMenuItem {
        let item = NSMenuItem(title: mode.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for duration in SleepPreventionDuration.allCases {
            let durationItem = NSMenuItem(title: duration.title, action: #selector(startSleepPrevention(_:)), keyEquivalent: "")
            durationItem.target = self
            durationItem.representedObject = SleepPreventionMenuSelection(mode: mode, duration: duration)
            submenu.addItem(durationItem)
        }
        item.submenu = submenu
        return item
    }

    @objc private func startSleepPrevention(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? SleepPreventionMenuSelection else { return }
        viewModel.startSleepPrevention(mode: selection.mode, duration: selection.duration)
    }

    @objc private func stopSleepPrevention() {
        viewModel.stopSleepPrevention()
    }

    @objc private func refresh() {
        Task { await viewModel.refreshAll() }
    }

    @objc private func copyReport() {
        viewModel.copyReport()
    }

    @objc private func showSettings() {
        showPopover()
    }

    @objc private func quit() {
        viewModel.stopSleepPrevention()
        NSApplication.shared.terminate(nil)
    }
}

private final class SleepPreventionMenuSelection {
    let mode: SleepPreventionMode
    let duration: SleepPreventionDuration

    init(mode: SleepPreventionMode, duration: SleepPreventionDuration) {
        self.mode = mode
        self.duration = duration
    }
}
