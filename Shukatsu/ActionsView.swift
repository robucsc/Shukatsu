//
//  ActionsView.swift
//  Shukatsu
//
//  Created by rob on 9/9/25.
//


import SwiftUI

struct ActionsView: View {
    let opportunity: Opportunity?
    let onPrint: () -> Void
    let onCoverLetter: () -> Void
    let onResume: () -> Void

    init(opportunity: Opportunity?,
         onPrint: @escaping () -> Void = {},
         onCoverLetter: @escaping () -> Void = {},
         onResume: @escaping () -> Void = {}) {
        self.opportunity = opportunity
        self.onPrint = onPrint
        self.onCoverLetter = onCoverLetter
        self.onResume = onResume
    }

    var body: some View {
        HStack {
            Button(action: onPrint) {
                Label("", systemImage: "printer")
            }
            Spacer()
            Button(action: onResume) {
                Label("", systemImage: "doc.text")
            }
            Spacer()
            Button(action: onCoverLetter) {
                Label("", systemImage: "envelope")
            }
            Spacer()
        }
        .buttonStyle(.plain)
        .disabled(opportunity == nil)
    }
}
