//
//  ContentView.swift
//  cameraSwift
//
//  Created by Harrison Hall on 5/26/24.
//

import SwiftUI
import AVFoundation
import Cocoa
import CoreMediaIO
import SystemExtensions
import ScreenCaptureKit
import OSLog
import Combine

//
//struct ContentView: View {
//    @StateObject private var viewModel = CameraViewModel()
//    
//    var body: some View {
//        HStack {
//            VStack {
//                Button("Activate") { SystemExtensionManager.shared.installExtension() }
//                .padding()
//
//                Button("Deactivate") { SystemExtensionManager.shared.uninstallExtension() }
//                .padding()
//            }
//            .onAppear {
//                viewModel.start()
//            }
//            
//        }
//       
//    }
//}
//
//#Preview {
//    ContentView()
//}


struct ContentView: View {
    
    @State var userStopped = false
    @State var disableInput = false
    @State var isUnauthorized = false
    
    @StateObject var screenRecorder = ScreenRecorder()
    
    
    var body: some View {
        HSplitView {
            ConfigurationView(screenRecorder: screenRecorder, userStopped: $userStopped)
                .frame(minWidth: 300, maxWidth: 500)
                .disabled(disableInput)
            screenRecorder.capturePreview
                .frame( maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
                .padding(8)
                .overlay {
                    if userStopped {
                        Image(systemName: "nosign")
                            .font(.system(size: 250, weight: .bold))
                            .foregroundColor(Color(white: 0.3, opacity: 1.0))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: 0.0, opacity: 0.5))
                    }
                }
                .border(Color.black)
                .onAppear {
                    print("aspect ratio is: ", screenRecorder.contentSize)
                }
            
            CameraView()
                .frame( maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(AspectRatio.aspectRatio, contentMode: .fit)
                .padding(8)
                .border(Color.black)
        }
        .background(Color.gray)
        .overlay {
            if isUnauthorized {
                VStack() {
                    Spacer()
                    VStack {
                        Text("No screen recording permission.")
                            .font(.largeTitle)
                            .padding(.top)
                        Text("Open System Settings and go to Privacy & Security > Screen Recording to grant permission.")
                            .font(.title2)
                            .padding(.bottom)
                    }
                    .frame(maxWidth: .infinity)
                    .background(.red)
                    
                }
            }
        }
        .navigationTitle("Screen Capture Sample")
        .onAppear {
            CameraViewModel.shared.start()
            Task {
                if await screenRecorder.canRecord {
                    await screenRecorder.start()
                } else {
                    isUnauthorized = true
                    disableInput = true
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}











class CameraViewModel: ObservableObject  {
    
    static let shared = CameraViewModel()
    
    private init() {
        // private initializer to prevent creating new instances
    }

    private var debugCaption: NSTextField!
    private var needToStreamCaption: NSTextField!
    private var needToStream: Bool = false
    private var mirrorCamera: Bool = false
    private var image = NSImage(named: "cham-index")
    private var activating: Bool = false
    private var readyToEnqueue = false
    private var enqueued = false
    private var _videoDescription: CMFormatDescription!
    private var _bufferPool: CVPixelBufferPool!
    private var _bufferAuxAttributes: NSDictionary!
    private var _whiteStripeStartRow: UInt32 = 0
    private var _whiteStripeIsAscending: Bool = false
    private var overlayMessage: Bool = false
    private var sequenceNumber = 0
    private var timer: Timer?
    private var propTimer: Timer?
    var sourceStream: CMIOStreamID?
    var sinkStream: CMIOStreamID?
    var sinkQueue: CMSimpleQueue?


    
    private class func _extensionBundle() -> Bundle {
        let extensionsDirectoryURL = URL(fileURLWithPath: "Contents/Library/SystemExtensions", relativeTo: Bundle.main.bundleURL)
        let extensionURLs: [URL]
        do {
            extensionURLs = try FileManager.default.contentsOfDirectory(at: extensionsDirectoryURL,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: .skipsHiddenFiles)
        } catch let error {
            fatalError("Failed to get the contents of \(extensionsDirectoryURL.absoluteString): \(error.localizedDescription)")
        }
        
        guard let extensionURL = extensionURLs.first else {
            fatalError("Failed to find any system extensions")
        }
        guard let extensionBundle = Bundle(url: extensionURL) else {
            fatalError("Failed to find any system extensions")
        }
        return extensionBundle
    }
    
    func getJustProperty(streamId: CMIOStreamID) -> String? {
        let selector = FourCharCode("just")
        var address = CMIOObjectPropertyAddress(selector, .global, .main)
        let exists = CMIOObjectHasProperty(streamId, &address)
        if exists {
            var dataSize: UInt32 = 0
            var dataUsed: UInt32 = 0
            CMIOObjectGetPropertyDataSize(streamId, &address, 0, nil, &dataSize)
            var name: CFString = "" as NSString
            CMIOObjectGetPropertyData(streamId, &address, 0, nil, dataSize, &dataUsed, &name);
            return name as String
        } else {
            return nil
        }
    }

    func setJustProperty(streamId: CMIOStreamID, newValue: String) {
        let selector = FourCharCode("just")
        var address = CMIOObjectPropertyAddress(selector, .global, .main)
        let exists = CMIOObjectHasProperty(streamId, &address)
        if exists {
            var settable: DarwinBoolean = false
            CMIOObjectIsPropertySettable(streamId,&address,&settable)
            if settable == false {
                return
            }
            var dataSize: UInt32 = 0
            CMIOObjectGetPropertyDataSize(streamId, &address, 0, nil, &dataSize)
            var newName: CFString = newValue as NSString
            CMIOObjectSetPropertyData(streamId, &address, 0, nil, dataSize, &newName)
        }
    }

    func makeDevicesVisible(){
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow : UInt32 = 1
        let dataSize : UInt32 = 4
        let zero : UInt32 = 0
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, zero, nil, dataSize, &allow)
    }
    
    func initSink(deviceId: CMIODeviceID, sinkStream: CMIOStreamID) {

        /// `Creating a Buffer Pool`
        // TODO: Potentailly delete this
        /// This video format only seems ot be being used for the buffer pool that the static image is drawn into. It may be able to be deleted.
        /// This seems to be only for the CVPixelBufferPoolCreate(). Which is the buffer pool used for the static image.
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: pixelFormat,
            width: fixedCamWidth, height: fixedCamHeight, extensions: nil, formatDescriptionOut: &_videoDescription)
        
        // TODO: and this?
        /// This seems to be for the CVPixelBufferPoolCreate() as well.
        let pixelBufferAttributes: NSDictionary = [
                kCVPixelBufferWidthKey: fixedCamWidth,
                kCVPixelBufferHeightKey: fixedCamHeight,
                kCVPixelBufferPixelFormatTypeKey: _videoDescription.mediaSubType,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        // TODO: and this too?
        /// The point of this seems to be to create a buffer pool for the static image in the enqueue function. This doesnt actaully
        /// have anything to do with the actual sink stream I think.
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &_bufferPool)

        
        
        
        /// `Connecting to the Sink Stream`
//      /// The syntax for the Unmanaged<> type is: Unmanaged<Type>, thats why you see the CMSimpleQ
        let pointerQueue = UnsafeMutablePointer<Unmanaged<CMSimpleQueue>?>.allocate(capacity: 1)
        // see https://stackoverflow.com/questions/53065186/crash-when-accessing-refconunsafemutablerawpointer-inside-cgeventtap-callback
        //let pointerRef = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        let pointerRef = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = CMIOStreamCopyBufferQueue(sinkStream, {
            (sinkStream: CMIOStreamID, buf: UnsafeMutableRawPointer?, refcon: UnsafeMutableRawPointer?) in
            let sender = Unmanaged<CameraViewModel>.fromOpaque(refcon!).takeUnretainedValue()
            sender.readyToEnqueue = true
        },pointerRef,pointerQueue)
        if result != 0 {
//            showMessage("error starting sink")
            print("error starting sink")
        } else {
            if let queue = pointerQueue.pointee {
                self.sinkQueue = queue.takeUnretainedValue()
            }
            let resultStart = CMIODeviceStartStream(deviceId, sinkStream) == 0
            if resultStart {
//                showMessage("initSink started")
                print("initSink started")
            } else {
//                showMessage("initSink error startstream")
                print("initSink error startstream")
            }
        }
    }

    
    
    
    func getDevice(name: String) -> AVCaptureDevice? {
        print("getDevice name=",name)
        var devices: [AVCaptureDevice]?
        if #available(macOS 10.15, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown],
                                                                    mediaType: .video,
                                                                    position: .unspecified)
            devices = discoverySession.devices
        } else {
            // Fallback on earlier versions
            devices = AVCaptureDevice.devices(for: .video)
        }
        guard let devices = devices else { return nil }
        return devices.first { $0.localizedName == name}
    }

    func getCMIODevice(uid: String) -> CMIOObjectID? {
        var dataSize: UInt32 = 0
        var devices = [CMIOObjectID]()
        var dataUsed: UInt32 = 0
        var opa = CMIOObjectPropertyAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), .global, .main)
        CMIOObjectGetPropertyDataSize(CMIOObjectPropertySelector(kCMIOObjectSystemObject), &opa, 0, nil, &dataSize);
        let nDevices = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        devices = [CMIOObjectID](repeating: 0, count: Int(nDevices))
        CMIOObjectGetPropertyData(CMIOObjectPropertySelector(kCMIOObjectSystemObject), &opa, 0, nil, dataSize, &dataUsed, &devices);
        for deviceObjectID in devices {
            opa.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)
            CMIOObjectGetPropertyDataSize(deviceObjectID, &opa, 0, nil, &dataSize)
            var name: CFString = "" as NSString
            //CMIOObjectGetPropertyData(deviceObjectID, &opa, 0, nil, UInt32(MemoryLayout<CFString>.size), &dataSize, &name);
            CMIOObjectGetPropertyData(deviceObjectID, &opa, 0, nil, dataSize, &dataUsed, &name);
            if String(name) == uid {
                return deviceObjectID
            }
        }
        return nil
    }

    func getInputStreams(deviceId: CMIODeviceID) -> [CMIOStreamID]
    {
        var dataSize: UInt32 = 0
        var dataUsed: UInt32 = 0
        var opa = CMIOObjectPropertyAddress(CMIOObjectPropertySelector(kCMIODevicePropertyStreams), .global, .main)
        CMIOObjectGetPropertyDataSize(deviceId, &opa, 0, nil, &dataSize);
        let numberStreams = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        var streamIds = [CMIOStreamID](repeating: 0, count: numberStreams)
        CMIOObjectGetPropertyData(deviceId, &opa, 0, nil, dataSize, &dataUsed, &streamIds)
        return streamIds
    }
    func connectToCamera() {
        if let device = getDevice(name: cameraName), let deviceObjectId = getCMIODevice(uid: device.uniqueID) {
            let streamIds = getInputStreams(deviceId: deviceObjectId)
            if streamIds.count == 2 {
                sinkStream = streamIds[1]
//                showMessage("found sink stream")
                print("found sink stream")
                initSink(deviceId: deviceObjectId, sinkStream: streamIds[1])
            }
            if let firstStream = streamIds.first {
//                showMessage("found source stream")
                print("found source stream")
                sourceStream = firstStream
            }
        }
    }
    
 

    func registerForDeviceNotifications() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVCaptureDeviceWasConnected, object: nil, queue: nil) { (notif) -> Void in
            // when the user click "activate", we will receive a notification
            // we can then try to connect to our "Sample Camera" (if not already connected to)
            if self.sourceStream == nil {
                self.connectToCamera()
            }
        }
    }

    func start() {

        registerForDeviceNotifications()
        self.makeDevicesVisible()
        connectToCamera()
//        timer?.invalidate()
//        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(fireTimer), userInfo: nil, repeats: true)
        propTimer?.invalidate()
        propTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(propertyTimer), userInfo: nil, repeats: true)
    }


    func enqueue(_ queue: CMSimpleQueue, _ image: CGImage) {
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else {
            print("error enqueuing")
            return
        }
        var err: OSStatus = 0
        var pixelBuffer: CVPixelBuffer?
        err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, self._bufferPool, self._bufferAuxAttributes, &pixelBuffer)
        if let pixelBuffer = pixelBuffer {
            
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            

            let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            // optimizing context: interpolationQuality and bitmapInfo
            // see https://stackoverflow.com/questions/7560979/cgcontextdrawimage-is-extremely-slow-after-large-uiimage-drawn-into-it
            if let context = CGContext(data: pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: rgbColorSpace,
                                      //bitmapInfo: UInt32(CGImageAlphaInfo.noneSkipFirst.rawValue) | UInt32(CGImageByteOrderInfo.order32Little.rawValue))
                                       bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            {
                context.interpolationQuality = .low
                if mirrorCamera {
                    context.translateBy(x: CGFloat(width), y: 0.0)
                    context.scaleBy(x: -1.0, y: 1.0)
                }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            
            var sbuf: CMSampleBuffer!
            var timingInfo = CMSampleTimingInfo()
            timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
            err = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: self._videoDescription, sampleTiming: &timingInfo, sampleBufferOut: &sbuf)
            if err == 0 {
                if let sbuf = sbuf {
                    let pointerRef = UnsafeMutableRawPointer(Unmanaged.passRetained(sbuf).toOpaque())
                    print("CMSampleBuffer is: ", sbuf)
                    CMSimpleQueueEnqueue(queue, element: pointerRef)
                }
            }
        } else {
            print("error getting pixel buffer")
        }
    }
    
    func enqueue(_ queue: CMSimpleQueue, _ sampleBuffer: CMSampleBuffer) {
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else {
            print("error enqueuing")
            return
        }
        let pointerRef = UnsafeMutableRawPointer(Unmanaged.passRetained(sampleBuffer).toOpaque())
        CMSimpleQueueEnqueue(queue, element: pointerRef)
    }
    
    @objc func propertyTimer() {
        if let sourceStream = sourceStream {
            self.setJustProperty(streamId: sourceStream, newValue: "random")
            let just = self.getJustProperty(streamId: sourceStream)
            if let just = just {
                if just == "sc=1" {
                    needToStream = true
                } else {
                    needToStream = false
                }
            }
//            print("need to stream = \(needToStream)")
        }
    }
    
    @objc func fireTimer() {
        if needToStream {
            
            if (enqueued == false || readyToEnqueue == true) {
                
                if let queue = self.sinkQueue {
                    
                    enqueued = true
                    readyToEnqueue = false
                    
                    if let image = image {
                        
                        if  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            
                            self.enqueue(queue, cgImage)
                        }
                    }
                }
            }
        }
    }
    
    @objc func fireTimer(_ sampleBuffer: CMSampleBuffer) {
        if needToStream {
            
            if (enqueued == false || readyToEnqueue == true) {
                
                if let queue = self.sinkQueue {
                    
                    enqueued = true
                    readyToEnqueue = false
                    
                    
                    // Normal
//                    print("CMSample buffer is: ", sampleBuffer)
//                        self.enqueue(queue, sampleBuffer)
                    
                    // Convereted
//                    if let convertedSampleBuffer = convertSampleBuffer(sampleBuffer) {
//                        
//                        print("Converted Sample buffer is: ", convertedSampleBuffer)
//                        print("Converted Sample buffer Format Description is: ", convertedSampleBuffer.formatDescription)
//                        self.enqueue(queue, convertedSampleBuffer)
//                        
//                    }
                    
                    // Striped
                    if let stripedSampleBuffer = stripMetadata(from: sampleBuffer) {
                        
//                        print("Striped Sample buffer is: ", stripedSampleBuffer)
//                        print("Striped Sample buffer Format Description is: ", stripedSampleBuffer.formatDescription)
//                        print("processed sample buffer is: ", str)
                        self.enqueue(queue, stripedSampleBuffer)
                    }
                }
            }
        }
    }
    
    
    
    func stripMetadata(from sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("Failed to get necessary components from sample buffer")
            return nil
        }
        
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)
        
        var newSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        
        if status != noErr {
            print("Failed to create new sample buffer: \(status)")
            return nil
        }
        
        
        return newSampleBuffer
    }
    
    
    
    

}



extension FourCharCode: ExpressibleByStringLiteral {
    
    public init(stringLiteral value: StringLiteralType) {
        var code: FourCharCode = 0
        // Value has to consist of 4 printable ASCII characters, e.g. '420v'.
        // Note: This implementation does not enforce printable range (32-126)
        if value.count == 4 && value.utf8.count == 4 {
            for byte in value.utf8 {
                code = code << 8 + FourCharCode(byte)
            }
        }
        else {
            print("FourCharCode: Can't initialize with '\(value)', only printable ASCII allowed. Setting to '????'.")
            code = 0x3F3F3F3F // = '????'
        }
        self = code
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self = FourCharCode(stringLiteral: value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self = FourCharCode(stringLiteral: value)
    }
    
    public init(_ value: String) {
        self = FourCharCode(stringLiteral: value)
    }
    
    public var string: String? {
        let cString: [CChar] = [
            CChar(self >> 24 & 0xFF),
            CChar(self >> 16 & 0xFF),
            CChar(self >> 8 & 0xFF),
            CChar(self & 0xFF),
            0
        ]
        return String(cString: cString)
    }
}

public extension CMIOObjectPropertyAddress {
    init(_ selector: CMIOObjectPropertySelector,
         _ scope: CMIOObjectPropertyScope = .anyScope,
         _ element: CMIOObjectPropertyElement = .anyElement) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

public extension CMIOObjectPropertyScope {
    /// The CMIOObjectPropertyScope for properties that apply to the object as a whole.
    /// All CMIOObjects have a global scope and for some it is their only scope.
    static let global = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)
    
    /// The wildcard value for CMIOObjectPropertyScopes.
    static let anyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard)
    
    /// The CMIOObjectPropertyScope for properties that apply to the input signal paths of the CMIODevice.
    static let deviceInput = CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput)
    
    /// The CMIOObjectPropertyScope for properties that apply to the output signal paths of the CMIODevice.
    static let deviceOutput = CMIOObjectPropertyScope(kCMIODevicePropertyScopeOutput)
    
    /// The CMIOObjectPropertyScope for properties that apply to the play through signal paths of the CMIODevice.
    static let devicePlayThrough = CMIOObjectPropertyScope(kCMIODevicePropertyScopePlayThrough)
}

public extension CMIOObjectPropertyElement {
    /// The CMIOObjectPropertyElement value for properties that apply to the master element or to the entire scope.
    //static let master = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
    static let main = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    /// The wildcard value for CMIOObjectPropertyElements.
    static let anyElement = CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
}
