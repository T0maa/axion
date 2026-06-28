//
//  GetCurrentDateTimeTool.swift
//  AXION
//
//  Created by Thomas Chamard on 21/06/2026.
//

import Foundation

final class GetCurrentDateTimeTool: Tool {
    let name = "get_current_datetime"

    func execute(argument: String) async -> ToolExecutionResult {
        let formatter = DateFormatter()

        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"

        return .success(title: "Current date and time", detail: formatter.string(from: Date()))
    }
}
