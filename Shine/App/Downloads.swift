import UIKit

/// Where the site's downloads land - the code block download button, generated
/// images - and how they get handed to the user.
enum ShineDownloads {
    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Keeps the filename the server suggested, without letting it escape the
    /// downloads folder or quietly overwrite an earlier download.
    static func destination(for suggestedFilename: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let raw = (suggestedFilename as NSString).lastPathComponent
        let name = raw.isEmpty ? "download" : raw

        var candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        repeat {
            let next = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(next)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)

        return candidate
    }

    static func share(_ url: URL) {
        guard let host = UIViewController.topMost else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: host.view.bounds.midX, y: host.view.bounds.maxY - 40, width: 1, height: 1
        )
        host.present(sheet, animated: true)
    }

    static func reportFailure(_ error: Error) {
        guard let host = UIViewController.topMost else { return }
        let alert = UIAlertController(
            title: "Download failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        host.present(alert, animated: true)
    }
}
