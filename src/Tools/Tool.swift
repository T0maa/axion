//
//  Tool.swift
//  AXION
//
//  Created by Thomas Chamard on 13/05/2026.
//

protocol Tool {
    var name: String { get }

    func execute(argument: String) -> String
}
