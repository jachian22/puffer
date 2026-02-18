import Foundation
import LocalAuthentication

public protocol LAContextProtocol {
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(
        _ policy: LAPolicy,
        localizedReason: String,
        reply: @escaping @Sendable (Bool, Error?) -> Void
    )
}

public final class SystemLAContextAdapter: LAContextProtocol {
    private let context: LAContext

    public init(context: LAContext = LAContext()) {
        self.context = context
    }

    public func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        context.canEvaluatePolicy(policy, error: error)
    }

    public func evaluatePolicy(
        _ policy: LAPolicy,
        localizedReason: String,
        reply: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        context.evaluatePolicy(policy, localizedReason: localizedReason, reply: reply)
    }
}

public struct LABiometricAuthorizer: BiometricAuthorizing {
    private let contextFactory: () -> LAContextProtocol

    public init(contextFactory: @escaping () -> LAContextProtocol = { SystemLAContextAdapter() }) {
        self.contextFactory = contextFactory
    }

    public func authorize(reason: String) async -> Bool {
        let context = contextFactory()

        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evalError) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
