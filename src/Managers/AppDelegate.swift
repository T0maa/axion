//
//  AppDelegate.swift
//  AXION
//
//  Created by Thomas Chamard on 12/05/2026.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    private let llamaServer = LlamaServerManager()
    private let settings = SettingsManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotkey()
        llamaServer.start(settings: settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalHotkeyMonitor {
            NSEvent.removeMonitor(globalHotkeyMonitor)
        }

        if let localHotkeyMonitor {
            NSEvent.removeMonitor(localHotkeyMonitor)
        }

        llamaServer.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        guard let button = statusItem?.button else {
            return
        }

        button.image = NSImage(
            systemSymbolName: "brain",
            accessibilityDescription: "AXION"
        )

        button.action = #selector(toggleWindow)
        button.target = self
    }

    @objc private func toggleWindow() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }

        showWindow()
    }

    private func showWindow() {
        if window == nil {
            let contentView = ChatView()
                .environmentObject(llamaServer)
                .environmentObject(settings)

            let hostingController = NSHostingController(rootView: contentView)

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            newWindow.contentViewController = hostingController
            newWindow.title = "AXON"
            newWindow.isReleasedWhenClosed = false
            newWindow.level = .floating

            window = newWindow
        }

        positionWindowBelowStatusItem()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionWindowBelowStatusItem() {
        guard let button = statusItem?.button,
              let window else {
            return
        }

        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let windowSize = window.frame.size

        let x = buttonFrame.midX - windowSize.width / 2
        let y = buttonFrame.minY - windowSize.height - 8

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func setupHotkey() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleHotkey(event)
        }

        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleHotkey(event)
            return event
        }
    }

    private func handleHotkey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )

        guard flags == [.control, .option],
              event.keyCode == 49 else {
            return
        }

        DispatchQueue.main.async {
            self.toggleWindow()
        }
    }
}
