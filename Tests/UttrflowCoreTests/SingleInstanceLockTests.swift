import Darwin
import Foundation
import Testing

@testable import UttrflowCore

@Suite("One copy of the app per user")
struct SingleInstanceLockTests {
    /// A fresh folder per test, so parallel tests never share a lock file.
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "single-instance-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func isHeldElsewhere(_ outcome: SingleInstanceLock.Outcome) -> Bool {
        if case .heldElsewhere = outcome { return true }
        return false
    }

    /// Starts a separate process that holds `file` for `seconds` and exits, returning once it says it holds it.
    private func holder(of file: URL, forSeconds seconds: Double = 60) throws -> Process {
        let script = """
            import fcntl, sys, time
            f = open(sys.argv[1], "a")
            fcntl.flock(f, fcntl.LOCK_EX)
            print("held", flush=True)
            time.sleep(float(sys.argv[2]))
            """
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [
            "python3", "-c", script, file.path(percentEncoded: false), String(seconds),
        ]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let line = output.fileHandleForReading.availableData
        try #require(String(decoding: line, as: UTF8.self).hasPrefix("held"))
        return process
    }

    @Test("The first copy takes the lock, creating its folder.")
    func firstAcquireSucceeds() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SingleInstanceLock.defaultFile(in: folder)
        guard case .acquired(let lock) = SingleInstanceLock.acquire(at: file) else {
            Issue.record("the first acquire did not take the lock")
            return
        }
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        withExtendedLifetime(lock) {}
    }

    @Test("A second copy is refused while the first holds the lock, and admitted once it lets go.")
    func secondAcquireFailsUntilRelease() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SingleInstanceLock.defaultFile(in: folder)
        // Scoped, so the first lock is freed at the brace and nothing else can keep it alive.
        do {
            guard case .acquired(let first) = SingleInstanceLock.acquire(at: file) else {
                Issue.record("the first acquire did not take the lock")
                return
            }
            let second = SingleInstanceLock.acquire(at: file)
            withExtendedLifetime(first) {}
            #expect(isHeldElsewhere(second))
        }
        guard case .acquired = SingleInstanceLock.acquire(at: file) else {
            Issue.record("releasing the first lock did not free it")
            return
        }
    }

    @Test("A lock held by another process refuses this one, and killing that process frees it.")
    func anotherProcessHoldsUntilKilled() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SingleInstanceLock.defaultFile(in: folder)
        let process = try holder(of: file)
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }

        #expect(isHeldElsewhere(SingleInstanceLock.acquire(at: file)))

        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        guard case .acquired = SingleInstanceLock.acquire(at: file) else {
            Issue.record("a killed holder left the lock behind")
            return
        }
    }

    @Test("Waiting takes the lock once a holder that is quitting exits.")
    func waitingOutlastsAQuittingHolder() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SingleInstanceLock.defaultFile(in: folder)
        // The holder quits on its own, so nothing here depends on another thread being scheduled in time.
        let process = try holder(of: file, forSeconds: 1.5)
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        #expect(isHeldElsewhere(SingleInstanceLock.acquire(at: file)))

        let outcome = SingleInstanceLock.acquire(at: file, waitingUpTo: .seconds(20))
        guard case .acquired = outcome else {
            Issue.record("the wait gave up before the holder exited")
            return
        }
    }

    @Test("Waiting gives up with the lock still held elsewhere once the time is spent.")
    func waitingGivesUp() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SingleInstanceLock.defaultFile(in: folder)
        guard case .acquired(let lock) = SingleInstanceLock.acquire(at: file) else {
            Issue.record("the first acquire did not take the lock")
            return
        }
        let outcome = SingleInstanceLock.acquire(
            at: file, waitingUpTo: .milliseconds(120), pollingEvery: .milliseconds(20))
        #expect(isHeldElsewhere(outcome))
        withExtendedLifetime(lock) {}
    }

    @Test("The lock is not inherited by a process this one launches.")
    func descriptorClosesOnExec() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        guard
            case .acquired(let lock) = SingleInstanceLock.acquire(
                at: SingleInstanceLock.defaultFile(in: folder))
        else {
            Issue.record("the first acquire did not take the lock")
            return
        }
        #expect(fcntl(lock.descriptor, F_GETFD) & FD_CLOEXEC != 0)
    }

    @Test("A folder that cannot be made reports the lock unavailable rather than held.")
    func unmakeableFolderIsUnavailable() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blocker = folder.appending(path: LocalStore.folder, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(atPath: blocker.path(percentEncoded: false), contents: Data()))
        guard case .unavailable = SingleInstanceLock.acquire(at: SingleInstanceLock.defaultFile(in: folder))
        else {
            Issue.record("a file in the folder's place was not reported unavailable")
            return
        }
    }

    @Test("A lock path that cannot be opened reports the lock unavailable.")
    func unopenableFileIsUnavailable() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SingleInstanceLock.defaultFile(in: folder)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        guard case .unavailable(let code) = SingleInstanceLock.acquire(at: file) else {
            Issue.record("a directory at the lock path was not reported unavailable")
            return
        }
        #expect(code == EISDIR)
    }
}
