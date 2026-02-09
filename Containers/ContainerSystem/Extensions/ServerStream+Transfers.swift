//
//  SandboxedBuilder+Extension.swift
//  Containers
//
//  Created by Axel Martinez on 9/2/26.
//

import ContainerBuild

extension ServerStream {
    func getImageTransfer() -> ImageTransfer? {
        guard case .imageTransfer(let transfer) = self.packetType else {
            return nil
        }
        return transfer
    }
    
    func getBuildTransfer() -> BuildTransfer? {
        guard case .buildTransfer(let transfer) = self.packetType else {
            return nil
        }
        return transfer
    }
    
    func getIO() -> IO? {
        guard case .io(let io) = self.packetType else {
            return nil
        }
        return io
    }
}
