//
//  ToolCall.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

import Foundation

struct ToolCall: Decodable {
    let tool: String
    let param: String?
    let params: [String: String]?

    init(tool: String, param: String? = nil, params: [String: String]? = nil) {
        self.tool = tool
        self.param = param
        self.params = params
    }

    var argument: String {
        if let params = params {
            switch tool {
            case "open_app":
                return params["app"] ?? ""

            case "open_url":
                return params["url"] ?? ""

            case "open_file", "reveal_file", "read_text_file":
                return params["path"] ?? ""

            case "copy_to_clipboard":
                return params["text"] ?? ""

            case "create_text_file", "append_text_file":
                let path = params["path"] ?? ""
                let content = params["content"] ?? ""
                return "\(path)|\(content)"

            case "get_current_datetime":
                return ""

            default:
                return params["value"] ?? ""
            }
        }

        return param ?? ""
    }
}
