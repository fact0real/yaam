import Foundation

// Keep at most one expensive snapshot running, even when it cannot stop immediately.
@MainActor
final class LatestSnapshotWorker<Key: Equatable & Sendable, Input: Sendable, Output: Sendable> {
    struct Result: Sendable {
        let key: Key
        let value: Output
    }

    private struct Request: Sendable {
        let key: Key
        let input: Input
        let generation: UInt64
        let operation: @Sendable (Input) -> Output?
    }

    private let debounce: Duration
    private var generation: UInt64 = 0
    private var requestedKey: Key?
    private var pending: Request?
    private var cached: Result?
    private var runner: Task<Result?, Never>?
    private var worker: Task<Output?, Never>?

    init(debounce: Duration = .milliseconds(300)) {
        self.debounce = debounce
    }

    func invalidate() {
        generation &+= 1
        requestedKey = nil
        pending = nil
        cached = nil
        worker?.cancel()
        // Retain the runner until its worker exits; cancellation is cooperative.
    }

    func value(
        for key: Key,
        input: Input,
        operation: @escaping @Sendable (Input) -> Output?
    ) async -> Result? {
        if let cached, cached.key == key { return cached }

        if requestedKey != key {
            generation &+= 1
            requestedKey = key
            pending = Request(key: key, input: input, generation: generation, operation: operation)
            worker?.cancel()
        }

        if runner == nil {
            runner = Task { await self.run() }
        }
        return await runner?.value
    }

    private func run() async -> Result? {
        while let request = pending {
            pending = nil
            try? await Task.sleep(for: debounce)
            guard request.generation == generation else { continue }

            let task = Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return nil as Output? }
                let value = request.operation(request.input)
                return Task.isCancelled ? nil : value
            }
            worker = task
            let output = await task.value
            worker = nil

            guard request.generation == generation else { continue }
            let result = output.map { Result(key: request.key, value: $0) }
            cached = result
            requestedKey = nil
            runner = nil
            return result
        }
        runner = nil
        return nil
    }
}
