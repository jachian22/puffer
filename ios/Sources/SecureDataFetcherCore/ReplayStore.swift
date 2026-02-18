import Foundation

public protocol ReplayStore {
    func hasSeen(nonce: String) async -> Bool
    func markSeen(nonce: String) async
}

public actor InMemoryReplayStore: ReplayStore {
    private var seen: Set<String> = []

    public init() {}

    public func hasSeen(nonce: String) -> Bool {
        seen.contains(nonce)
    }

    public func markSeen(nonce: String) {
        seen.insert(nonce)
    }
}
