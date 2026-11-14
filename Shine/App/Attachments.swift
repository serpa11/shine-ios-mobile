import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Presents the native picker behind a web file input.
///
/// `WKWebView` hands a file input to `runOpenPanelWith`. Offering only a
/// document picker would mean the site's attachment chip can never reach the
/// camera, so an image-accepting input gets the full choice: camera, photo
/// library, or files.
///
/// Picked items are copied into a temporary directory before being handed back.
/// `WKWebView` keeps the URLs for the life of the upload, and a security-scoped
/// URL from the picker can be revoked underneath it.
final class AttachmentPicker: NSObject {

    private var completion: (([URL]?) -> Void)?
    private var allowsMultiple = false
    private var tempDirectory: URL?

    // MARK: - Entry point

    func present(from presenter: UIViewController,
                 types: [UTType],
                 allowsMultiple: Bool,
                 completion: @escaping ([URL]?) -> Void) {
        self.completion = completion
        self.allowsMultiple = allowsMultiple

        let wantsImages = !types.isEmpty && types.allSatisfy { $0.conforms(to: .image) }
        if wantsImages {
            offerImageChoices(from: presenter)
        } else {
            presentDocumentPicker(from: presenter, types: types)
        }
    }

    private func finish(_ urls: [URL]?) {
        let completion = self.completion
        self.completion = nil

        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
            self.tempDirectory = nil
        }
        completion?(urls)
    }

    // MARK: - Image sources

    private func offerImageChoices(from presenter: UIViewController) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentCamera(from: presenter)
            })
        }
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPhotoLibrary(from: presenter)
        })
        sheet.addAction(UIAlertAction(title: "Browse Files", style: .default) { [weak self] _ in
            self?.presentDocumentPicker(from: presenter, types: [UTType.image, UTType.movie, UTType.data])
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.finish(nil)
        })

        // An action sheet on iPad needs an anchor or it will not appear.
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1
        )
        presenter.present(sheet, animated: true)
    }

    private func presentCamera(from presenter: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentPhotoLibrary(from presenter: UIViewController) {
        var config = PHPickerConfiguration()
        config.filter = .images
        // PHPicker needs no photo library permission prompt, and the user can
        // pick from the whole library rather than only what the app can see.
        config.selectionLimit = allowsMultiple ? 10 : 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentDocumentPicker(from presenter: UIViewController, types: [UTType]) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func stagingDirectory() throws -> URL {
        if let tempDirectory { return tempDirectory }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shine-upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectory = dir
        return dir
    }
}

// MARK: - Camera

extension AttachmentPicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.9) else {
            finish(nil)
            return
        }

        do {
            let dir = try stagingDirectory()
            let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: url)
            finish([url])
        } catch {
            finish(nil)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(nil)
    }
}

// MARK: - Photo library

extension AttachmentPicker: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            finish(nil)
            return
        }

        // Each item arrives on its own callback, so they are collected and the
        // web view is answered once the last one lands.
        let group = DispatchGroup()
        var urls: [URL] = []
        var failed = false

        for result in results {
            group.enter()
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { failed = true; return }
                do {
                    let dir = try self.stagingDirectory()
                    let destination = dir.appendingPathComponent(url.lastPathComponent)
                    // The provider URL is only valid for this callback.
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    urls.append(destination)
                } catch {
                    failed = true
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // An empty result would look to the web view like a cancelled pick.
            self.finish(urls.isEmpty && !failed ? nil : urls)
        }
    }
}

// MARK: - Files

extension AttachmentPicker: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }
}
