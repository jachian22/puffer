import Foundation

public struct KeychainAccessPolicy: Equatable, Sendable {
    public let accessibleClass: String
    public let requiresCurrentBiometricSet: Bool
    public let deviceOnly: Bool

    public init(accessibleClass: String, requiresCurrentBiometricSet: Bool, deviceOnly: Bool) {
        self.accessibleClass = accessibleClass
        self.requiresCurrentBiometricSet = requiresCurrentBiometricSet
        self.deviceOnly = deviceOnly
    }

    public static let mvpDefault = KeychainAccessPolicy(
        accessibleClass: "kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
        requiresCurrentBiometricSet: true,
        deviceOnly: true
    )
}

public struct WebViewSessionPolicy: Equatable, Sendable {
    public let isPersistent: Bool
    public let clearsCookiesPerExecution: Bool

    public init(isPersistent: Bool, clearsCookiesPerExecution: Bool) {
        self.isPersistent = isPersistent
        self.clearsCookiesPerExecution = clearsCookiesPerExecution
    }

    public static let mvpDefault = WebViewSessionPolicy(
        isPersistent: false,
        clearsCookiesPerExecution: true
    )
}
