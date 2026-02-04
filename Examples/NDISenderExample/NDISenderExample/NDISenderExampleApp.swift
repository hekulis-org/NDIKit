//
//  NDISenderExampleApp.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import SwiftUI
import NDIKit

@main
struct NDISenderExampleApp: App {
    init() {
        if !NDI.initialize() {
            print("Warning: NDI initialization failed - CPU may not be supported")
        } else {
            print("NDI initialized successfully, version: \(NDI.version)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
