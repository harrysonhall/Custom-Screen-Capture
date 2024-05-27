//
//  main.swift
//  Extension
//
//  Created by Harrison Hall on 5/26/24.
//

import Foundation
import CoreMediaIO

let providerSource = cameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()

