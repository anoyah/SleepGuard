//
//  SleepGuardApp.swift
//  SleepGuard
//
//  Created by Yother Liu on 2026/6/3.
//

import SwiftUI

@main
struct SleepGuardApp: App {
    @StateObject private var viewModel = SleepGuardViewModel()

    var body: some Scene {
        MenuBarExtra {
            SleepGuardRootView(viewModel: viewModel)
                .frame(width: 390, height: 560)
                .task {
                    await viewModel.start()
                }
                .onDisappear {
                    viewModel.stopAutoRefresh()
                }
        } label: {
            Image(systemName: viewModel.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
