import Foundation

final class FileMonitor {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pending: DispatchWorkItem?

    func start(watching fileURL: URL, onChange: @escaping () -> Void) {
        stop()
        let directory = fileURL.deletingLastPathComponent()
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            pending?.cancel()
            let work = DispatchWorkItem {
                DispatchQueue.main.async(execute: onChange)
            }
            pending = work
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(220), execute: work)
        }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit { stop() }
}
