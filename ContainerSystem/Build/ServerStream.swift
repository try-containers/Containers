//
//  ServerStream.swift
//  Containers
//
//  Represents a message from the builder server (BuildKit) to the client.
//

import Foundation

/// Represents a message received from the builder server.
public struct ServerStream: Sendable, Codable {

    /// The type of packet contained in this message.
    public enum PacketType: Sendable, Codable {
        case imageTransfer(ImageTransfer)
        case buildTransfer(BuildTransfer)
        case io(IO)
        case buildError(BuildError)
        case commandComplete
        case none
    }

    public var buildID: String = ""
    public var packetType: PacketType = .none

    public init() {}

    public func getImageTransfer() -> ImageTransfer? {
        guard case .imageTransfer(let transfer) = self.packetType else {
            return nil
        }
        return transfer
    }

    public func getBuildTransfer() -> BuildTransfer? {
        guard case .buildTransfer(let transfer) = self.packetType else {
            return nil
        }
        return transfer
    }

    public func getIO() -> IO? {
        guard case .io(let io) = self.packetType else {
            return nil
        }
        return io
    }
}
