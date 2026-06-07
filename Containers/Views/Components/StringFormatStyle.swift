//
//  StringFormatStyle.swift
//  Containers
//
//  Created by Axel Martinez on 2026/06/06.
//

import Foundation

struct StringFormatStyle: ParseableFormatStyle {
    typealias FormatInput = String
    typealias FormatOutput = String
    
    func format(_ value: String) -> String {
        value
    }
    
    var parseStrategy: StringParseStrategy {
        StringParseStrategy()
    }
}

struct StringParseStrategy: ParseStrategy {
    typealias ParseInput = String
    typealias ParseOutput = String
    
    func parse(_ value: String) throws -> String {
        value
    }
}
