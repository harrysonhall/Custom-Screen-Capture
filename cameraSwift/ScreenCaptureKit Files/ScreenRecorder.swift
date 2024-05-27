/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A model object that provides the interface to capture screen content and system audio.
*/
import Foundation
import ScreenCaptureKit
import Combine
import OSLog
import SwiftUI



@MainActor
class ScreenRecorder: NSObject, ObservableObject {
    
    /// The supported capture types.
    enum CaptureType {
        case display
        case window
    }
    // Combine subscribers.
    private var subscriptions = Set<AnyCancellable>()
    private let captureEngine = CaptureEngine()
    private var availableApps = [SCRunningApplication]()
    @Published private(set) var availableDisplays = [SCDisplay]()
    @Published private(set) var availableWindows = [SCWindow]()
    private let logger = Logger()
    private var isSetup = false
    @Published var isRunning = false
    @Published var captureType: CaptureType = .display {
        didSet { updateEngine() }
    }
    @Published var selectedDisplay: SCDisplay? {
        didSet { updateEngine() }
    }
    @Published var selectedWindow: SCWindow? {
        didSet { updateEngine() }
    }
    @Published var isAppExcluded = true {
        didSet { updateEngine() }
    }
    @Published var contentSize = CGSize(width: 1, height: 1)
    private var scaleFactor: Int { Int(NSScreen.main?.backingScaleFactor ?? 2) }
    
    /// A view that renders the screen content.
    lazy var capturePreview: CapturePreview = {
        CapturePreview()
    }()


    
    /// `Permissions Check`
    /// This is soley a permissions check, this makes a call to SCShareableContent to attempt to fetch the available content to capture
    /// if this application does not have the proper permissions, this call will throw an error, which is all we are looking for with this function.
    /// Is to see if this call throws an error or not.
    var canRecord: Bool {
        get async {
            do {
                // If the app doesn't have screen recording permission, this call generates an exception.
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                return false
            }
        }
    }
    
    ///  `Update Filter`
    private var contentFilter: SCContentFilter {
        var filter: SCContentFilter
        switch captureType {
            case .display:
                guard let display = selectedDisplay else { fatalError("No display selected.") }
                var excludedApps = [SCRunningApplication]()
                // If a user chooses to exclude the app from the stream,
                // exclude it by matching its bundle identifier.
                if isAppExcluded {
                    excludedApps = availableApps.filter { app in
                        Bundle.main.bundleIdentifier == app.bundleIdentifier
                    }
                }
                // Create a content filter with excluded apps.
                filter = SCContentFilter(display: display,
                                         excludingApplications: excludedApps,
                                         exceptingWindows: [])
            case .window:
                guard let window = selectedWindow else { fatalError("No window selected.") }
                
                // Create a content filter that includes a single window.
                filter = SCContentFilter(desktopIndependentWindow: window)
        }

        return filter
    }
    
    private var streamConfiguration: SCStreamConfiguration {
        
        let streamConfig = SCStreamConfiguration()
        
        // Configure the display content width and height.
        if captureType == .display, let display = selectedDisplay {
            streamConfig.width = display.width * scaleFactor
            streamConfig.height = display.height * scaleFactor
        }
        
        // Configure the window content width and height.
        if captureType == .window, let window = selectedWindow {
            streamConfig.width = Int(window.frame.width) * 2
            streamConfig.height = Int(window.frame.height) * 2
        }
        
        // Set the capture interval at 60 fps.
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        
        // Increase the depth of the frame queue to ensure high fps at the expense of increasing
        // the memory footprint of WindowServer.
        streamConfig.queueDepth = 5
        
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        
        return streamConfig
    }
    
    
    
    
    /// `Functions`
    func monitorAvailableContent() async {
        // Refresh the lists of capturable content.
        await self.refreshAvailableContent()
        Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.refreshAvailableContent()
            }
        }
        .store(in: &subscriptions)
    }
    
    
    private func refreshAvailableContent() async {
        do {
            // Retrieve the available screen content to capture.
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                        onScreenWindowsOnly: true)
            availableDisplays = availableContent.displays
            
            let windows = filterWindows(availableContent.windows)
            if windows != availableWindows {
                availableWindows = windows
            }
            availableApps = availableContent.applications
            
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
            if selectedWindow == nil {
                selectedWindow = availableWindows.first
            }
        } catch {
            logger.error("Failed to get the shareable content: \(error.localizedDescription)")
        }
    }
    
    
    /// Starts capturing screen content.
    func start() async {
        // Exit early if already running.
        guard !isRunning else { return }
        
        if !isSetup {
            // Starting polling for available screen content.
            await monitorAvailableContent()
            isSetup = true
        }
        
        do {
            let config = streamConfiguration
            let filter = contentFilter
            // Update the running state.
            isRunning = true
            // Start the stream and await new video frames.
            
            /// `Loop Creation`
            /// This is where the streams loop is created. It's created using by iterating over an Asyncronous Sequence
            for try await frame in captureEngine.startCapture(configuration: config, filter: filter) {
                capturePreview.updateFrame(frame)
                if contentSize != frame.size {
                    // Update the content size if it changed.
                    contentSize = frame.size
                    
                }
            }
        } catch {
            logger.error("\(error.localizedDescription)")
            // Unable to start the stream. Set the running state to false.
            isRunning = false
        }
    }
    
    /// Stops capturing screen content.
    func stop() async {
        guard isRunning else { return }
        await captureEngine.stopCapture()
        isRunning = false
    }
    
    
    /// - Tag: UpdateCaptureConfig
    private func updateEngine() {
        guard isRunning else { return }
        Task {
            let filter = contentFilter
            await captureEngine.update(configuration: streamConfiguration, filter: filter)
        }
    }

    
    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows
        // Sort the windows by app name.
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
        
        // TODO: Remove these two other filters, just leave the sorted
        // Remove windows that don't have an associated .app bundle.
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
        // Remove this app's window from the list.
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
}






/// `Extensions`
extension SCWindow {
    var displayName: String {
        switch (owningApplication, title) {
        case (.some(let application), .some(let title)):
            return "\(application.applicationName): \(title)"
        case (.none, .some(let title)):
            return title
        case (.some(let application), .none):
            return "\(application.applicationName): \(windowID)"
        default:
            return ""
        }
    }
}

extension SCDisplay {
    var displayName: String {
        "Display: \(width) x \(height)"
    }
}
