//
//  KippleApp.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI

@main
struct KippleApp: App {
    @StateObject private var menuBarApp = MenuBarApp()
    
    init() {
        // App initialization
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
