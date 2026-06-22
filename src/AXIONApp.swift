//
//  AXIONApp.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import SwiftUI

@main
struct AXIONApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
