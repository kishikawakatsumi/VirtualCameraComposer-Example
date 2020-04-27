import Cocoa
import AVFoundation

@objcMembers
class VideoComposer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
//    private let screenCapture = ScreenCapture()
    private let cameraCapture = CameraCapture()

    private let context = CIContext()
    private var lastScreenImageBuffer: CVImageBuffer?

    weak var delegate: VideoComposerDelegate?

    private let session = URLSession(configuration: .default)
    private var settings = [String: Any]()

    deinit {
        stopRunning()
    }

    func startRunning() {
        startPollingSettings()

//        screenCapture.output.setSampleBufferDelegate(self, queue: .main)
        cameraCapture.output.setSampleBufferDelegate(self, queue: .main)
        
//        screenCapture.startRunning()
        cameraCapture.startRunning()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            if let windowID = self.settings["windowID"] as? Int,
                let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(windowID), [.bestResolution, .boundsIgnoreFraming]) {
                let ciImage = CIImage(cgImage: windowImage)

                if let text = self.settings["text"] as? String, !text.isEmpty {
                    let bitmapImageRep = NSBitmapImageRep(ciImage: ciImage)
                    let g = NSGraphicsContext(bitmapImageRep: bitmapImageRep)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = g

                    (text as NSString).draw(at: NSPoint(x: 200, y: ciImage.extent.height - 400), withAttributes: [.font : NSFont.boldSystemFont(ofSize: 400), .foregroundColor: NSColor.black])

                    NSGraphicsContext.restoreGraphicsState()

                    if let textImage = CIImage(bitmapImageRep: bitmapImageRep) {
                        var pixelBuffer: CVPixelBuffer?
                        let options: [String: Any] = [
                            kCVPixelBufferCGImageCompatibilityKey as String: true,
                            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                        ]

                        _ = CVPixelBufferCreate(
                            kCFAllocatorDefault,
                            Int(textImage.extent.size.width),
                            Int(textImage.extent.height),
                            kCVPixelFormatType_32BGRA,
                            options as CFDictionary,
                            &pixelBuffer
                        )

                        if let pixelBuffer = pixelBuffer {
                            self.context.render(textImage, to: pixelBuffer)
                            self.lastScreenImageBuffer = pixelBuffer
                            return
                        }
                    }
                }

                var pixelBuffer: CVPixelBuffer?
                let options: [String: Any] = [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]

                _ = CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    Int(ciImage.extent.size.width),
                    Int(ciImage.extent.height),
                    kCVPixelFormatType_32BGRA,
                    options as CFDictionary,
                    &pixelBuffer
                )

                if let pixelBuffer = pixelBuffer {
                    self.context.render(ciImage, to: pixelBuffer)
                    self.lastScreenImageBuffer = pixelBuffer
                }
            }
        }
        timer.fire()
    }

    func stopRunning() {
//        screenCapture.stopRunning()
        cameraCapture.stopRunning()
    }

    func startPollingSettings() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let container = URL(fileURLWithPath: NSTemporaryDirectory())
            let settingsURL = container.appendingPathComponent("Settings.json")
            if let jsonObject = try? JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL), options: []) as? [String: Any] {
                self.settings = jsonObject
            } else {
                let request = URLRequest(url: URL(string: "http://127.0.0.1:50000/settings")!)
                self.session.dataTask(with: request) { (data, res, _) in
                    if let data = data, let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        self.settings = jsonObject
                    }
                }
                .resume()
            }
        }
        timer.fire()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == self.cameraCapture.output {
            let cameraOverlayPosition = settings["cameraOverlayPosition"] as? Int ?? 1

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let cameraImage = CIImage(cvImageBuffer: imageBuffer)

            guard let screenImageBuffer = lastScreenImageBuffer else { return }
            let screenImage = CIImage(cvImageBuffer: screenImageBuffer)

            let translatedCameraImage: CIImage
            switch cameraOverlayPosition {
            case 0:
                translatedCameraImage = cameraImage.transformed(by: CGAffineTransform(translationX: 0, y: screenImage.extent.height - cameraImage.extent.height))
            case 1:
                translatedCameraImage = cameraImage
            case 2:
                translatedCameraImage = cameraImage.transformed(by: CGAffineTransform(translationX: screenImage.extent.width - cameraImage.extent.width, y: 0))
            case 3:
                translatedCameraImage = cameraImage.transformed(by: CGAffineTransform(translationX: screenImage.extent.width - cameraImage.extent.width, y: screenImage.extent.height - cameraImage.extent.height))
            default:
                translatedCameraImage = cameraImage
            }

            let compositedImage = translatedCameraImage.composited(over: screenImage)

            var pixelBuffer: CVPixelBuffer?
            let options: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]

            _ = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(compositedImage.extent.size.width),
                Int(compositedImage.extent.height),
                kCVPixelFormatType_32BGRA,
                options as CFDictionary,
                &pixelBuffer
            )

            if let pixelBuffer = pixelBuffer {
                context.render(compositedImage, to: pixelBuffer)
                delegate?.videoComposer(self, didComposeImageBuffer: pixelBuffer)
            }
        }
    }
}

@objc
protocol VideoComposerDelegate: class {
    func videoComposer(_ composer: VideoComposer, didComposeImageBuffer imageBuffer: CVImageBuffer)
}
