//
//  ClientStream.swift
//  Containers
//
//  Represents a message from the client to the builder server (BuildKit).
//

import Foundation

/// Represents a message sent from the client to the builder server.
public struct ClientStream: Sendable, Codable {

    /// The type of packet contained in this message.
    public enum PacketType: Sendable, Codable {
        case imageTransfer(ImageTransfer)
        case buildTransfer(BuildTransfer)
        case command(BuildCommand)
        case none
    }

    public var buildID: String = ""
    public var imageTransfer: ImageTransfer = ImageTransfer()
    public var buildTransfer: BuildTransfer = BuildTransfer()
    public var command: BuildCommand = BuildCommand()
    public var packetType: PacketType = .none

    public init() {}
}
