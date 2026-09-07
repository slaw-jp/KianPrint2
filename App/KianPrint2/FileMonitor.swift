import Darwin
import Foundation

/// Watches both the parent directory and the file's stat signature.
///
/// Editors such as mi.app may save either in place or by atomically replacing
/// the original file. Directory events catch replacements, while polling the
/// inode and nanosecond mtime makes reload reliable even when a filesystem
/// event is coalesced or omitted.
final class FileMonitor {
    private struct Signature: Equatable {
        var device: UInt64
        var inode: UInt64
        var size: Int64
        var modifiedSeconds: Int64
        var modifiedNanoseconds: Int64
    }

    private var directorySource: DispatchSourceFileSystemObject?
    private var pollingSource: DispatchSourceTimer?
    private var directoryDescriptor: Int32 = -1
    private var pending: DispatchWorkItem?
    private var fileURL: URL?
    private var lastSignature: Signature?
    private var onChange: (() -> Void)?

    func start(watching fileURL: URL, onChange: @escaping () -> Void) {
        stop()
        self.fileURL = fileURL.standardizedFileURL
        self.onChange = onChange
        lastSignature = signature(of: fileURL)

        let directory = fileURL.deletingLastPathComponent()
        directoryDescriptor = open(directory.path, O_EVTONLY)
        if directoryDescriptor >= 0 {
            let descriptor = directoryDescriptor
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend, .attrib, .link, .revoke],
                queue: .main
            )
            source.setEventHandler { [weak self] in self?.detectChange() }
            source.setCancelHandler { close(descriptor) }
            directorySource = source
            source.resume()
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.detectChange() }
        pollingSource = timer
        timer.resume()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        directorySource?.cancel()
        directorySource = nil
        pollingSource?.cancel()
        pollingSource = nil
        directoryDescriptor = -1
        fileURL = nil
        lastSignature = nil
        onChange = nil
    }

    private func detectChange() {
        guard let fileURL else { return }
        let nextSignature = signature(of: fileURL)
        guard nextSignature != lastSignature else { return }
        lastSignature = nextSignature
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    private func signature(of url: URL) -> Signature? {
        var value = Darwin.stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return Signature(
            device: UInt64(value.st_dev),
            inode: UInt64(value.st_ino),
            size: Int64(value.st_size),
            modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec)
        )
    }

    deinit { stop() }
}
