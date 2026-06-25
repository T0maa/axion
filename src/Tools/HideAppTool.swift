//
//  HideAppTool.swift
//  AXION
//
//  Created by Thomas Chamard on 22/06/2026.
//

import AppKit

final class HideAppTool: Tool {
    let name = "hide_app"

    func execute(argument: String) -> ToolExecutionResult {
        let appName = clean(argument)

        guard !appName.isEmpty else {
            return .failure(title: "Missing app name")
        }

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.lowercased() == appName.lowercased()
        }

        guard let app = apps.first else {
            return .failure(title: "App is not running", detail: appName)
        }

        app.hide()

        if app.isHidden {
            return .success(title: "App hidden", detail: appName)
        }

        return .success(title: "Hide command sent", detail: appName)
    }

    private func clean(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }
}
