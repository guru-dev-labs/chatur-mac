//
//  AppDelegate.swift
//  Chatur
//
//  Created by Deevanshu Guru on 17/08/25.
//

import SwiftUI
import AppKit

// This class allows us to tap into the application's lifecycle.
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // This function is called as soon as the app is ready to run.
        
        // We find the main window of our application.
        if let window = NSApplication.shared.windows.first {
            
            // This makes the window's own background transparent.
            window.backgroundColor = .clear
            
            // This tells the window it can be transparent.
            window.isOpaque = false
            
            // This is another way to ensure the title bar is hidden.
            window.styleMask.remove(.titled)
        }
    }
}
