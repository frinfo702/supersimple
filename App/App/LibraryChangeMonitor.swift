import Darwin
import Foundation

/// Watches the notes directory without polling. Atomic saves appear as directory
/// write/rename events, so one vnode source covers editors, iCloud, and terminal tools.
final class LibraryChangeMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.frinfo702.supersimple.library-monitor")
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?

    func start(directory: URL, onChange: @escaping @Sendable () -> Void) {
        stop()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(descriptor)
        }

        lock.lock()
        self.source = source
        lock.unlock()
        source.resume()
    }

    func stop() {
        lock.lock()
        let existing = source
        source = nil
        lock.unlock()
        existing?.cancel()
    }

    deinit {
        stop()
    }
}
