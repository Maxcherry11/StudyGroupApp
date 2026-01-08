import Foundation

final class CardsFetchCoordinator {
    static let shared = CardsFetchCoordinator()

    private let stateQueue = DispatchQueue(label: "CardsFetchCoordinator.state")
    private var inFlightTask: Task<[Card], Never>?
    private var inFlightKey: String?
    private var pendingKey: String?
    private var pendingNames: [String]?
    private var pendingReason: String?
    private var pendingContinuations: [CheckedContinuation<[Card], Never>] = []
    private var pendingReady = false
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.35

    private init() {}

    func requestFetch(names: [String], reason: String) async -> [Card] {
        let normalized = normalize(names)
        return await withCheckedContinuation { continuation in
            stateQueue.async {
                if normalized.names.isEmpty {
                    self.log("skip", "reason=\(reason) (empty names)")
                    continuation.resume(returning: [])
                    return
                }

                let key = normalized.key
                if let inFlightTask = self.inFlightTask, self.inFlightKey == key {
                    self.log("join", "reason=\(reason) count=\(normalized.names.count) names=\(self.preview(normalized.names))")
                    Task {
                        let result = await inFlightTask.value
                        continuation.resume(returning: result)
                    }
                    return
                }

                if self.inFlightTask != nil {
                    self.log("queue", "reason=\(reason) count=\(normalized.names.count) names=\(self.preview(normalized.names))")
                    self.pendingKey = key
                    self.pendingNames = normalized.names
                    self.pendingReason = reason
                    self.pendingContinuations.append(continuation)
                    self.pendingReady = true
                    return
                }

                self.pendingKey = key
                self.pendingNames = normalized.names
                self.pendingReason = reason
                self.pendingContinuations.append(continuation)
                self.scheduleDebounce(reason: reason, names: normalized.names)
            }
        }
    }

    private func scheduleDebounce(reason: String, names: [String]) {
        debounceWorkItem?.cancel()
        log("schedule", "reason=\(reason) count=\(names.count) names=\(preview(names))")
        let workItem = DispatchWorkItem { [weak self] in
            self?.stateQueue.async {
                guard let self else { return }
                self.pendingReady = true
                self.startPendingIfPossible()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func startPendingIfPossible() {
        guard inFlightTask == nil else { return }
        guard pendingReady, let names = pendingNames, let key = pendingKey else { return }

        let reason = pendingReason ?? "unknown"
        let continuations = pendingContinuations
        pendingContinuations = []
        pendingReady = false
        pendingKey = nil
        pendingNames = nil
        pendingReason = nil

        log("start", "reason=\(reason) count=\(names.count) names=\(preview(names))")
        let task = Task { await fetchCards(names: names) }
        inFlightTask = task
        inFlightKey = key

        Task { [weak self] in
            let result = await task.value
            let continuationsToResume = continuations
            self?.stateQueue.async {
                guard let self else { return }
                self.inFlightTask = nil
                self.inFlightKey = nil
                self.log("complete", "reason=\(reason) count=\(result.count) names=\(self.preview(names))")
                if self.pendingReady {
                    self.startPendingIfPossible()
                }
            }
            for continuation in continuationsToResume {
                continuation.resume(returning: result)
            }
        }
    }

    private func fetchCards(names: [String]) async -> [Card] {
        await withCheckedContinuation { continuation in
            CloudKitManager.fetchCards(requestedNames: names) { cards in
                continuation.resume(returning: cards)
            }
        }
    }

    private func normalize(_ names: [String]) -> (names: [String], key: String) {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let unique = Array(Set(cleaned)).sorted()
        let key = unique.joined(separator: "|")
        return (unique, key)
    }

    private func preview(_ names: [String]) -> String {
        let preview = names.prefix(8).joined(separator: ", ")
        let suffix = names.count > 8 ? ", ..." : ""
        return "[\(preview)\(suffix)]"
    }

    private func log(_ action: String, _ message: String) {
        print("🧭 [CARDS COORD] \(action) \(message)")
    }
}
