import CMySQL
import Foundation

/// A dedicated OS thread that owns one MySQL connection.
///
/// libmysqlclient expects every thread that touches a `MYSQL*` to have called
/// `mysql_thread_init()`, and its calls block on network I/O. Pinning each
/// connection to its own thread satisfies the first requirement and keeps the
/// blocking calls off Swift's cooperative thread pool.
final class ConnectionThread: @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var isStopping = false

    init(name: String) {
        // The thread retains `self` until `stop()` lets the loop drain and exit.
        let thread = Thread { [self] in loop() }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func submit(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            submit { continuation.resume(with: Result(catching: body)) }
        }
    }

    /// Lets already-submitted jobs finish, then ends the thread.
    func stop() {
        condition.lock()
        isStopping = true
        condition.signal()
        condition.unlock()
    }

    private func loop() {
        mysql_thread_init()
        defer { mysql_thread_end() }
        while true {
            condition.lock()
            while jobs.isEmpty && !isStopping {
                condition.wait()
            }
            if jobs.isEmpty {
                condition.unlock()
                return
            }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
    }
}
