import Darwin
import Foundation

enum ProcessLockFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case alreadyRunning
    case system(code: Int32, message: String)

    var description: String {
        switch self {
        case .alreadyRunning:
            "Another BitPrice process already owns this data directory"
        case .system(_, let message):
            message
        }
    }
}

final class ProcessLock {
    let lockURL: URL
    private var descriptor: Int32

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        lockURL = rootDirectory.appendingPathComponent("instance.lock", isDirectory: false)
        let opened = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard opened >= 0 else {
            let code = errno
            throw ProcessLockFailure.system(code: code, message: "Could not open instance lock: \(String(cString: strerror(code)))")
        }
        descriptor = opened
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(opened)
            descriptor = -1
            if code == EWOULDBLOCK {
                throw ProcessLockFailure.alreadyRunning
            }
            throw ProcessLockFailure.system(code: code, message: "Could not acquire instance lock: \(String(cString: strerror(code)))")
        }
    }

    deinit {
        if descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
    }
}
