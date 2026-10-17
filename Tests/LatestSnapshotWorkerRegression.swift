// swiftc -swift-version 6 -default-isolation MainActor -parse-as-library YAAM/LatestSnapshotWorker.swift Tests/LatestSnapshotWorkerRegression.swift -o /tmp/yaam-snapshot-regression
import Foundation

private nonisolated final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var peak = 0
    private var inputs: [Int] = []
    let release = DispatchSemaphore(value: 0)

    func compute(_ value: Int, block: Bool = false) -> Int {
        lock.lock()
        running += 1
        peak = max(peak, running)
        inputs.append(value)
        lock.unlock()
        if block { precondition(release.wait(timeout: .now() + 10) == .success) }
        lock.lock()
        running -= 1
        lock.unlock()
        return value * 10
    }

    var state: (peak: Int, inputs: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        return (peak, inputs)
    }
}

@main
struct LatestSnapshotWorkerRegression {
    @MainActor
    static func main() async {
        await burstAndCache()
        await supersedeUncooperativeWork()
        await invalidateAndReuseKey()
        await cancelledWaiterDoesNotCancelSharedWork()
        await invalidateBeforeWorkStarts()
        print("Latest snapshot worker regression tests passed (5 scenarios).")
    }

    @MainActor
    private static func burstAndCache() async {
        let worker = LatestSnapshotWorker<Int, Int, Int>(debounce: .milliseconds(40))
        let probe = Probe()
        var waiters: [Task<LatestSnapshotWorker<Int, Int, Int>.Result?, Never>] = []
        for key in 0..<100 {
            waiters.append(Task {
                await worker.value(for: key, input: key) { probe.compute($0) }
            })
            await Task.yield()
        }
        for waiter in waiters {
            let result = await waiter.value
            precondition(result?.key == 99 && result?.value == 990)
        }
        let cached = await worker.value(for: 99, input: 99) { probe.compute($0) }
        precondition(cached?.value == 990)
        precondition(probe.state.inputs == [99])
    }

    @MainActor
    private static func supersedeUncooperativeWork() async {
        let worker = LatestSnapshotWorker<Int, Int, Int>(debounce: .milliseconds(5))
        let probe = Probe()
        let first = Task {
            await worker.value(for: 1, input: 1) { probe.compute($0, block: true) }
        }
        await waitUntil { probe.state.inputs == [1] }
        var waiters: [Task<LatestSnapshotWorker<Int, Int, Int>.Result?, Never>] = []
        for key in 2...50 {
            worker.invalidate()
            waiters.append(Task {
                await worker.value(for: key, input: key) { probe.compute($0) }
            })
            await Task.yield()
        }
        try? await Task.sleep(for: .milliseconds(20))
        precondition(probe.state.inputs == [1], "A replacement started before cancelled work exited")
        probe.release.signal()
        let originalResult = await first.value
        precondition(originalResult?.key == 50 && originalResult?.value == 500)
        for waiter in waiters {
            let result = await waiter.value
            precondition(result?.key == 50)
        }
        precondition(probe.state.peak == 1)
        precondition(probe.state.inputs == [1, 50])
    }

    @MainActor
    private static func invalidateAndReuseKey() async {
        let worker = LatestSnapshotWorker<Int, Int, Int>(debounce: .milliseconds(5))
        let probe = Probe()
        let first = Task {
            await worker.value(for: 1, input: 1) { probe.compute($0, block: true) }
        }
        await waitUntil { probe.state.inputs == [1] }
        worker.invalidate()
        probe.release.signal()
        let discarded = await first.value
        precondition(discarded == nil, "Invalidated output was published")
        let replacement = await worker.value(for: 1, input: 2) { probe.compute($0) }
        precondition(replacement?.value == 20, "Reused key returned an old profile's output")
        precondition(probe.state.peak == 1)
        precondition(probe.state.inputs == [1, 2])
    }

    @MainActor
    private static func cancelledWaiterDoesNotCancelSharedWork() async {
        let worker = LatestSnapshotWorker<Int, Int, Int>(debounce: .milliseconds(5))
        let probe = Probe()
        let first = Task {
            await worker.value(for: 1, input: 1) { probe.compute($0, block: true) }
        }
        await waitUntil { probe.state.inputs == [1] }
        first.cancel()
        let second = Task {
            await worker.value(for: 1, input: 1) { probe.compute($0) }
        }
        await Task.yield()
        probe.release.signal()
        let result = await second.value
        _ = await first.value
        precondition(result?.value == 10)
        precondition(probe.state.inputs == [1])
    }

    @MainActor
    private static func invalidateBeforeWorkStarts() async {
        let worker = LatestSnapshotWorker<Int, Int, Int>(debounce: .milliseconds(40))
        let probe = Probe()
        var registered = false
        let first = Task {
            registered = true
            return await worker.value(for: 1, input: 1) { probe.compute($0) }
        }
        await waitUntil { registered }
        worker.invalidate()
        let replacement = await worker.value(for: 2, input: 2) { probe.compute($0) }
        let original = await first.value
        precondition(original?.key == 2 && replacement?.value == 20)
        precondition(probe.state.inputs == [2], "Work invalidated during debounce still ran")
    }

    @MainActor
    private static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<2000 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Timed out waiting for the worker")
    }
}
