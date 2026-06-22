//
//  OpenAppTool.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

import AppKit

final class OpenAppTool: Tool {
    let name = "open_app"

    func execute(argument: String) -> String {
        let workspace = NSWorkspace.shared
        let bundleId = bundleId(for: argument)

        guard let appURL = workspace.urlForApplication(
            withBundleIdentifier: bundleId
        ) else {
            return "Unable to open \(argument)."
        }

        let configuration = NSWorkspace.OpenConfiguration()
        workspace.openApplication(at: appURL, configuration: configuration)

        return "Opened \(argument)."
    }

    private func bundleId(for appName: String) -> String {
        switch appName.lowercased() {
        case "safari":
            return "com.apple.Safari"
        case "terminal":
            return "com.apple.Terminal"
        case "finder":
            return "com.apple.finder"
        case "xcode":
            return "com.apple.dt.Xcode"
        default:
            return appName
        }
    }
}
