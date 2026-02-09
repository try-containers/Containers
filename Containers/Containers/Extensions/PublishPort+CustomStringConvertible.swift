//
//  PublishPort.swift
//  Containers
//
//  Created by Axel Martinez on 02/02/26.
//

import Foundation
import ContainerResource

extension PublishPort: @retroactive CustomStringConvertible {
    public var description: String {
        "\(self.hostPort):\(self.containerPort) (\(self.proto.rawValue.localizedUppercase))"
    }
}
