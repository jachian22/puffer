import Foundation

public enum RequestStateMachine {
    private static let allowed: Set<String> = [
        "PENDING_APPROVAL->APPROVED",
        "PENDING_APPROVAL->DENIED",
        "PENDING_APPROVAL->EXPIRED",
        "APPROVED->EXECUTING",
        "APPROVED->FAILED",
        "EXECUTING->COMPLETED",
        "EXECUTING->FAILED"
    ]

    public static func canTransition(from: RequestStatus, to: RequestStatus) -> Bool {
        allowed.contains("\(from.rawValue)->\(to.rawValue)")
    }
}
