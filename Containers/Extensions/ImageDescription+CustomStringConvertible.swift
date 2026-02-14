//
//  ImageDescription.swift
//  Containers
//
//  Created by Axel Martinez on 02/02/26.
//

import ContainerizationOCI
import ContainerResource

extension ImageDescription: @retroactive CustomStringConvertible {
    public var description: String {
        guard let annotations = self.descriptor.annotations else {
            return self.reference
        }
        
        if let name = annotations[AnnotationKeys.containerizationImageName] {
            return name
        }

        if let name = annotations[AnnotationKeys.containerdImageName] {
            return name
        }
        
        if let name = annotations[AnnotationKeys.openContainersImageName] {
            return name
        }

        return self.reference
    }
}
