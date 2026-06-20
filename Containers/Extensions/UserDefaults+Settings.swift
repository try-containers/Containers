//
//  SettingsManager.swift
//  Containers
//
//  Created by Axel Martinez on 02/02/26.
//

import Foundation

@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    var container: UserDefaults = UserDefaults.standard

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
    private static let applicationDataRootKey = "applicationDataRoot"
    private static let applicationDataRootBookmarkKey =
        "applicationDataRootBookmark"

    /// Returns the default app root inside the app sandbox.
    static var defaultAppRoot: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        .appendingPathComponent("app.containers")
    }

    /// Root directory for containers, images, volumes, kernels, and build data.
    static var applicationDataRoot: URL {
        get {
            if let bookmarkData = applicationDataRootBookmarkData {
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )

                    if isStale,
                        let refreshedBookmark = try? url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                    {
                        applicationDataRootBookmarkData = refreshedBookmark
                    }

                    return url
                } catch {
                    // Fall through to the stored URL or sandbox default if the bookmark can no longer resolve.
                }
            }

            return UserDefaults.standard.url(forKey: applicationDataRootKey)
                ?? defaultAppRoot
        }
        set {
            UserDefaults.standard.set(newValue, forKey: applicationDataRootKey)
        }
    }

    static var usesDefaultApplicationDataRoot: Bool {
        applicationDataRootBookmarkData == nil
            && applicationDataRoot.standardizedFileURL
                == defaultAppRoot.standardizedFileURL
    }

    static func setApplicationDataRoot(_ url: URL, bookmarkData: Data?) {
        applicationDataRoot = url
        applicationDataRootBookmarkData = bookmarkData
    }

    static func resetApplicationDataRoot() {
        UserDefaults.standard.removeObject(forKey: applicationDataRootKey)
        applicationDataRootBookmarkData = nil
    }

    private static var applicationDataRootBookmarkData: Data? {
        get {
            UserDefaults.standard.data(forKey: applicationDataRootBookmarkKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue,
                    forKey: applicationDataRootBookmarkKey
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: applicationDataRootBookmarkKey
                )
            }
        }
    }

    @UserDefault(key: "startSystemTimeoutSeconds", defaultValue: 10)
    static var startSystemTimeoutSeconds: Int32

    @UserDefault(key: "stopContainerTimeoutSeconds", defaultValue: 5)
    static var stopContainerTimeoutSeconds: Int32

    @UserDefault(key: "shutdownSystemTimeoutSeconds", defaultValue: 20)
    static var shutdownSystemTimeoutSeconds: Int32
}
