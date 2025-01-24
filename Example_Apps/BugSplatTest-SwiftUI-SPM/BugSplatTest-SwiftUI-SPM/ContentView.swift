//
//  ContentView.swift
//  BugSplatTest-SwiftUI-SPM
//
//  Created by David Ferrero on 1/23/25.
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
