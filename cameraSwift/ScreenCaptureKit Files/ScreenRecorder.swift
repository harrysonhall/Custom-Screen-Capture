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
    
    private let excludedApplicationsKey = "excludedApplications"
    
    /// The supported capture types.
    enum CaptureType {
        case display
        case window
    }
    
    override init() {
        super.init()
        
        // Load the initial value from User Defaults
        if let savedApplications = UserDefaults.standard.stringArray(forKey: excludedApplicationsKey) {
            excludedApplications = Set(savedApplications)
        }
        
        // Your other initialization code
        print("exluded applications are: ", excludedApplications)
    }
    
    
    // Combine subscribers.
    private var subscriptions = Set<AnyCancellable>()
    private let captureEngine = CaptureEngine()
    @Published private(set) var availableApps = [SCRunningApplication]()
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
    @Published var excludedApplications: Set<String> = [] {
        didSet {
            updateEngine()
            updatePreferencesForExcludedApplications()
        }
    }
    @Published var excludedWindows: Set<String> = [] {
        didSet {
            updateEngine()
        }
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
        
        guard let display = selectedDisplay else { fatalError("No display selected.") }
        
        var excludedApps = [SCRunningApplication]()
        // If a user chooses to exclude the app from the stream,
        // exclude it by matching its bundle identifier.
        if !excludedApplications.isEmpty {
            excludedApps = availableApps.filter { app in
                excludedApplications.contains(app.bundleIdentifier)
            }
        }
        
        var excludedWins = [SCWindow]()
        // If a user chooses to exclude windows from the stream,
        // exclude them by matching its owning applications bundle identifier and title.
        if !excludedWindows.isEmpty {
            excludedWins = availableWindows.filter { window in
                if let title = window.title, !title.isEmpty {
                    return excludedWindows.contains("\(window.owningApplication?.bundleIdentifier ?? "").\(title)")
                }
                return false
            }
        }
        print("Excluded Apps Updated: \(excludedApps)")
        
        // Create a content filter with excluded apps.
        filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: excludedWins)
     
        
        

        return filter
    }
    
    
    
    
    private var streamConfiguration: SCStreamConfiguration {
        
        let streamConfig = SCStreamConfiguration()
        
        // Configure the display content width and height.
        streamConfig.width = 1728
        streamConfig.height = 1118
        
        // Set the capture interval at 60 fps.
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        
        // Increase the depth of the frame queue to ensure high fps at the expense of increasing
        // the memory footprint of WindowServer.
        streamConfig.queueDepth = 5
        
//        streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        
        
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
                print("mointoring available content")
            }
        }
        .store(in: &subscriptions)
    }
    
    
    private func refreshAvailableContent() async {
        do {
            // Retrieve the available screen content to capture.
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly: false)
            
            availableDisplays = availableContent.displays
            
            // Refresh Applications
            let applications = filterApplications(availableContent.applications)
            if applications != availableApps {
                availableApps = applications
            }
            
            // Refresh Windows
            let windows = filterWindows(availableContent.windows)
            if windows != availableWindows {
                availableWindows = windows
            }
            
            
            
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
            // Filter out windows where the title is nil or an empty string
            .filter { !($0.title?.isEmpty ?? true) }
            // Sort the windows by title alphabetically
            .sorted { $0.title! < $1.title! }
        // Sort the windows by app name.
//            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
        // TODO: Remove these two other filters, just leave the sorted
        // Remove windows that don't have an associated .app bundle.
//            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
        // Remove this app's window from the list.
//            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
    
    private func filterApplications(_ applications: [SCRunningApplication]) -> [SCRunningApplication] {
        applications
            .sorted { $0.applicationName.lowercased() < $1.applicationName.lowercased() }
    }
    
    private func updatePreferencesForExcludedApplications() {
         UserDefaults.standard.set(Array(excludedApplications), forKey: "excludedApplications")
            print("Excluded App defaults updated")
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
