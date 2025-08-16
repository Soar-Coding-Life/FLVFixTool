//
//  FLVFixToolApp.swift
//  FLVFixTool
//
//  Created by 王贵彬 on 2025/8/16.
//

import SwiftUI

@main
struct FLVFixToolApp: App {
    // Create a single source of truth for the view
    @State private var contentView = ContentView()

    var body: some Scene {
        WindowGroup {
            contentView
                .onOpenURL { url in
                    // This gets called when a file is dropped on the app icon
                    // or opened with the app.
                    contentView.parseFile(at: url)
                }
        }
    }
}
