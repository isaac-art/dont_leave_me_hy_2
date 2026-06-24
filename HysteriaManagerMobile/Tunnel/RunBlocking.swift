import Foundation

/// Libbox invokes our platform-interface callbacks on its own threads and expects
/// synchronous returns, but our work (setTunnelNetworkSettings, NEHotspotNetwork…)
/// is async. These helpers bridge the two by blocking until the async work finishes.

func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {
        do { box.value = .success(try await operation()) }
        catch { box.value = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.value!.get()
}

@discardableResult
func runBlocking<T>(_ operation: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached {
        box.value = .success(await operation())
        semaphore.signal()
    }
    semaphore.wait()
    return (try? box.value!.get())!
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: Result<T, Error>?
}

struct ExtensionStartupError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
