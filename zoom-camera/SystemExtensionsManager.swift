import Foundation
import SystemExtensions

class SystemExtensionManager: NSObject, OSSystemExtensionRequestDelegate {
    
    static let shared = SystemExtensionManager()
    
    private override init() {}
    
    private let extensionIdentifier = "zoom-camera.Extension" // Explicitly set the bundle identifier of the system extension
     
     func installExtension() {
         print("Attempting to install")
         print("System extension identifier: ", extensionIdentifier)
         let activationRequest = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
         activationRequest.delegate = self
         OSSystemExtensionManager.shared.submitRequest(activationRequest)
     }
    
    func uninstallExtension() {
        guard let extensionIdentifier = SystemExtensionManager.extensionBundle()?.bundleIdentifier else {
            return
        }
        
        let deactivationRequest = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        deactivationRequest.delegate = self
        OSSystemExtensionManager.shared.submitRequest(deactivationRequest)
    }
    
    private static func extensionBundle() -> Bundle? {
        // Replace with the actual bundle identifier of your system extension
        return Bundle(identifier: "zoom-camera.Extension")
    }
    
    // MARK: - OSSystemExtensionRequestDelegate
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        // Handle success
        print("Request finished with result: \(result)")
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        // Handle failure
        print("Request failed with error: \(error)")
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // Handle user approval
        print("Request needs user approval")
    }
    
    func request(_ request: OSSystemExtensionRequest, didCancelWithError error: Error) {
        // Handle cancellation
        print("Request was cancelled with error: \(error)")
    }
    
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Decide what to do when replacing an existing extension with a new one
        // For now, simply replace the existing extension
        return .replace
    }
}
