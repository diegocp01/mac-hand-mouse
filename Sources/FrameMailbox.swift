import Foundation

/// Keeps at most one undelivered result while the main thread is busy.
final class LatestFrameBuffer<Value> {
    private let lock = NSLock()
    private var pending: Value?
    private var scheduled = false

    /// Returns true only when the caller needs to schedule a delivery.
    func offer(_ value: Value) -> Bool {
        lock.lock(); defer { lock.unlock() }
        pending = value
        if scheduled { return false }
        scheduled = true
        return true
    }

    func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        let value = pending
        pending = nil
        scheduled = false
        return value
    }
}
