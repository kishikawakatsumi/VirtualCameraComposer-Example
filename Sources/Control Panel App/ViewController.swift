import Cocoa
import Swifter

class ViewController: NSViewController {
    @IBOutlet private var arrayController: NSArrayController!
    @IBOutlet private var textField: NSTextField!
    private var kvoToken: NSObject?

    private let server = HttpServer()
    private let port: in_port_t = 50000

    override func viewDidLoad() {
        super.viewDidLoad()
        server.GET["/settings"] = { request -> HttpResponse in
            let semaphore = DispatchSemaphore(value: 0)

            var settings = [String: Any]()
            if let container: URL = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "27AEDK3C9F.com.kishikawakatsumi.VirtualCameraComposer") {
                let settingsURL = container.appendingPathComponent("Library/Preferences/Settings.json")

                if let jsonObject = try? JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL), options: []) as? [String: Any] {
                    settings = jsonObject
                    semaphore.signal()
                }
            }
            semaphore.wait()
            return .ok(.json(settings))
        }

        try? server.start(port, forceIPv4: true, priority: .default)

        kvoToken = arrayController.observe(\.selectionIndexes, options: [.new]) { (arrayController, change) in
            if let window = arrayController.selectedObjects.first as? NSDictionary, let windowID = window["windowID"] as? Int {
                guard let container: URL = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "27AEDK3C9F.com.kishikawakatsumi.VirtualCameraComposer") else { return }
                let settingsURL = container.appendingPathComponent("Library/Preferences/Settings.json")
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(writingItemAt: settingsURL, options: [], error: nil) { (URL) in
                    if var settings = try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL)) {
                        settings.windowID = windowID
                        try? JSONEncoder().encode(settings).write(to: settingsURL)
                    } else {
                        try? JSONEncoder().encode(Settings(windowID: windowID, cameraOverlayPosition: 1, text: "")).write(to: settingsURL)
                    }
                }
            }
        }

        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) {
            arrayController.content = (windowList as NSArray).filter{ (entry) -> Bool in
                if let entry = entry as? NSDictionary, let sharingState = entry[kCGWindowSharingState] as? Int, sharingState != CGWindowSharingType.none.rawValue {
                    return true
                }
                return false
            }
            .map { (entry) -> [String: Any] in
                var outputEntry = [String: Any]()
                if let entry = entry as? NSDictionary {
                    if let applicationName = entry[kCGWindowOwnerName] {
                        let nameAndPID = "\(applicationName) (\(entry[kCGWindowOwnerPID] ?? 0))"
                        outputEntry["applicationName"] = nameAndPID;
                    } else {
                        let nameAndPID = "((unknown)) (\(entry[kCGWindowOwnerPID] ?? 0))"
                        outputEntry["applicationName"] = nameAndPID;
                    }

                    if let windowBounds = entry[kCGWindowBounds], let bounds = CGRect(dictionaryRepresentation: windowBounds as! CFDictionary) {
                        outputEntry["windowOrigin"] = "\(bounds.origin.x)/\(bounds.origin.y)"
                        outputEntry["windowSize"] = "\(bounds.size.width)*\(bounds.size.height)"
                    }

                    if let windowID = entry[kCGWindowNumber], let windowLevel = entry[kCGWindowLayer] {
                        outputEntry["windowID"] = windowID
                        outputEntry["windowLevel"] = windowLevel
                    }
                }
                return outputEntry
            }
        }
    }

    @IBAction
    private func cameraOverlayPositionChanged(_ sender: NSPopUpButton) {
        guard let container: URL = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "27AEDK3C9F.com.kishikawakatsumi.VirtualCameraComposer") else { return }
        let settingsURL = container.appendingPathComponent("Library/Preferences/Settings.json")
        let fileCoordinator = NSFileCoordinator()
        fileCoordinator.coordinate(writingItemAt: settingsURL, options: [], error: nil) { (URL) in
            if var settings = try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL)) {
                settings.cameraOverlayPosition = sender.indexOfSelectedItem
                try? JSONEncoder().encode(settings).write(to: settingsURL)
            } else {
                try? JSONEncoder().encode(Settings(windowID: 0, cameraOverlayPosition: sender.indexOfSelectedItem, text: "")).write(to: settingsURL)
            }
        }
    }
}

extension ViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let container: URL = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "27AEDK3C9F.com.kishikawakatsumi.VirtualCameraComposer") else { return }
        let settingsURL = container.appendingPathComponent("Library/Preferences/Settings.json")
        let fileCoordinator = NSFileCoordinator()
        fileCoordinator.coordinate(writingItemAt: settingsURL, options: [], error: nil) { (URL) in
            if var settings = try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL)) {
                settings.text = textField.stringValue
                try? JSONEncoder().encode(settings).write(to: settingsURL)
            } else {
                try? JSONEncoder().encode(Settings(windowID: 0, cameraOverlayPosition: 1, text: textField.stringValue)).write(to: settingsURL)
            }
        }
    }
}

struct Settings: Codable {
    var windowID: Int
    var cameraOverlayPosition: Int
    var text: String
}
