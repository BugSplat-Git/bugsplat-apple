//
//  ContentView.swift
//  BugSplatTest-SwiftUI
//
//  Copyright © BugSplat, LLC. All rights reserved.
//

import SwiftUI

struct ContentView: View {

    let prop: Int? = nil

    var body: some View {
        Button("Crash!") {
            _ = prop!
        }
        .padding()
        .foregroundColor(.white)
        .background(Color.accentColor)
        .cornerRadius(10)
    }
}

#Preview {
    ContentView()
}
