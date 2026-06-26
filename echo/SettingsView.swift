//
//  SettingsView.swift
//  echo
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("General", value: SettingsPane.general)
            }
            .navigationSplitViewColumnWidth(150)
        } detail: {
            GeneralSettingsView()
        }
        .frame(width: 500, height: 300)
    }
}

enum SettingsPane: Hashable {
    case general
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("API") {
                Text("Groq API key — coming soon")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
