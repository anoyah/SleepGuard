//
//  SleepGuardApp.swift
//  SleepGuard
//
//  Created by Yother Liu on 2026/6/3.
//

import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = SleepGuardViewModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopSleepPrevention()
    }
}
