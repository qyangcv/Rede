//
//  MyReaderApp.swift
//  MyReader
//
//  Created by 杨权 on 2026/9/10.
//

import SwiftUI
import SwiftData

@main
struct MyReaderApp: App {
    @State private var session = ReaderSession()
    
    init () {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 600, height: 400)
        .modelContainer(.localLibrary)
        .environment(session)
        
        Window("Reader Window", id: ReaderSession.windowID) {
            ReaderWindow()
        }
        .defaultSize(width: 734, height: 861)
        .environment(session)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
