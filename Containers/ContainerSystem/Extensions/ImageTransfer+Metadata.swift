//
//  SandboxedBuilder+Extension.swift
//  Containers
//
//  Created by Axel Martinez on 9/2/26.
//

import Foundation
import ContainerBuild
import ContainerizationOCI

extension ImageTransfer {
    func stage() -> String? {
        self.metadata["stage"]
    }
    
    func method() -> String? {
        self.metadata["method"]
    }
    
    func ref() -> String? {
        self.metadata["ref"]
    }
    
    func platform() throws -> Platform? {
        guard let platform = self.metadata["platform"] else {
            return nil
        }
        return try Platform(from: platform)
    }
    
    init(id: String, digest: String, ref: String, platform: String, data: Data) throws {
        self.init()
        self.id = id
        self.tag = digest
        self.metadata = [
            "os": "linux",
            "stage": "resolver",
            "method": "/resolve",
            "ref": ref,
            "platform": platform,
        ]
        self.complete = true
        self.direction = .into
        self.data = data
    }
}
