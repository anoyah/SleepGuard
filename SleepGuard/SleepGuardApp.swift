import SwiftUI
import UserNotifications

@main
struct SleepGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let viewModel = SleepGuardViewModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        statusBarController = StatusBarController(viewModel: viewModel)
        Task { await viewModel.startBackgroundRefresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopSleepPrevention()
    }

    // 用户点击通知 → 打开 popover
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        statusBarController?.showPopoverFromNotification()
        completionHandler()
    }

    // app 在前台时也显示 banner
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
