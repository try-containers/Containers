//
//  ClientStream.swift
//  Containers
//
//  Type aliases and helpers for Apple container builder protobuf types.
//

import Containerization
import ContainerizationOCI
import Foundation

public typealias IO = Com_Apple_Container_Build_V1_IO
public typealias InfoRequest = Com_Apple_Container_Build_V1_InfoRequest
public typealias InfoResponse = Com_Apple_Container_Build_V1_InfoResponse
public typealias ClientStream = Com_Apple_Container_Build_V1_ClientStream
public typealias ServerStream = Com_Apple_Container_Build_V1_ServerStream
public typealias ImageTransfer = Com_Apple_Container_Build_V1_ImageTransfer
public typealias BuildTransfer = Com_Apple_Container_Build_V1_BuildTransfer

extension BuildTransfer {
    func stage() -> String? {
        let stage = self.metadata["stage"]
        return stage == "" ? nil : stage
    }

    func method() -> String? {
        let method = self.metadata["method"]
        return method == "" ? nil : method
    }

    func includePatterns() -> [String]? {
        guard let includePatternsString = self.metadata["include-patterns"] else {
            return nil
        }
        return includePatternsString == "" ? nil : includePatternsString.components(separatedBy: ",")
    }

    func followPaths() -> [String]? {
        guard let followPathString = self.metadata["followpaths"] else {
            return nil
        }
        return followPathString == "" ? nil : followPathString.components(separatedBy: ",")
    }

    func mode() -> String? {
        self.metadata["mode"]
    }

    func size() -> Int? {
        guard let sizeString = self.metadata["size"] else {
            return nil
        }
        return sizeString == "" ? nil : Int(sizeString)
    }

    func offset() -> UInt64? {
        guard let offsetString = self.metadata["offset"] else {
            return nil
        }
        return offsetString == "" ? nil : UInt64(offsetString)
    }

    func len() -> Int? {
        guard let lengthString = self.metadata["length"] else {
            return nil
        }
        return lengthString == "" ? nil : Int(lengthString)
    }
}

extension ImageTransfer {
    init(
        id: String,
        digest: String,
        ref: String,
        platform: String,
        data: Data
    ) throws {
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

    func mode() -> String? {
        self.metadata["mode"]
    }

    func size() -> Int? {
        guard let sizeString = self.metadata["size"] else {
            return nil
        }
        return Int(sizeString)
    }

    func len() -> Int? {
        guard let lengthString = self.metadata["length"] else {
            return nil
        }
        return Int(lengthString)
    }

    func offset() -> UInt64? {
        guard let offsetString = self.metadata["offset"] else {
            return nil
        }
        return UInt64(offsetString)
    }
}

extension ServerStream {
    func getImageTransfer() -> ImageTransfer? {
        if case .imageTransfer(let transfer) = self.packetType {
            return transfer
        }
        return nil
    }

    func getBuildTransfer() -> BuildTransfer? {
        if case .buildTransfer(let transfer) = self.packetType {
            return transfer
        }
        return nil
    }

    func getIO() -> IO? {
        if case .io(let io) = self.packetType {
            return io
        }
        return nil
    }
}
