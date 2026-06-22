//
//  FocusAppTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import AppKit

final class FocusAppTool: Tool {
    let name = "focus_app"

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

        if app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) {
            return "App focused: \(appName)"
        }

        return "Failed to focus app: \(appName)"
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
