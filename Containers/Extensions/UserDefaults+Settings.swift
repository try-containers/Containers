//
//  SettingsManager.swift
//  Containers
//
//  Created by Axel Martinez on 02/02/26.
//

import SwiftUI

@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    var container: UserDefaults = .standard

    var wrappedValue: Value {
        get {
            return container.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            container.set(newValue, forKey: key)
        }
    }
}

extension UserDefaults {
    /// Returns the app root following Apple's containerization pattern
    /// Uses Application Support directory with app-specific namespace
    static var defaultAppRoot: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        .appendingPathComponent("app.containers")
    }
    
    @UserDefault(
        key: "applicationDataRoot", 
        defaultValue: UserDefaults.defaultAppRoot
    )
    static var applicationDataRoot: URL
    
    @UserDefault(key: "startSystemTimeoutSeconds", defaultValue: 10)
    static var startSystemTimeoutSeconds: Int32
    
    @UserDefault(key: "stopContainerTimeoutSeconds", defaultValue: 5)
    static var stopContainerTimeoutSeconds: Int32
    
    @UserDefault(key: "shutdownSystemTimeoutSeconds", defaultValue: 20)
    static var shutdownSystemTimeoutSeconds: Int32
}
