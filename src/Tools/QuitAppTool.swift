//
//  QuitAppTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import AppKit

final class QuitAppTool: Tool {
    let name = "quit_app"

    func execute(argument: String) -> String {
        let appName = clean(argument)

        guard !appName.isEmpty else {
            return "Missing app name."
        }

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.lowercased() == appName.lowercased()
        }

        guard let app = apps.first else {
            return "App is not running: \(appName)"
        }

        if app.terminate() {
            return "App quit: \(appName)"
        }

        return "Failed to quit app: \(appName)"
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
