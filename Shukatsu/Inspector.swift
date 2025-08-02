//
//  Inspector.swift
//  Shukatsu
//
//  Created by rob on 9/9/25.
//


import Foundation
import SwiftUI
import Combine

enum InspectorBus {
    static let hide   = Notification.Name("HideInspector")
    static let show   = Notification.Name("ShowInspector")
    static let toggle = Notification.Name("ToggleInspector")

    static func hideNow()   { NotificationCenter.default.post(name: hide, object: nil) }
    static func showNow()   { NotificationCenter.default.post(name: show, object: nil) }
    static func toggleNow() { NotificationCenter.default.post(name: toggle, object: nil) }
}

// Expose the real inspector state/control via Environment
struct InspectorController {
    let isOpen: () -> Bool
    let show:   () -> Void
    let hide:   () -> Void
    let toggle: () -> Void
}

private struct InspectorControllerKey: EnvironmentKey {
    static let defaultValue = InspectorController(
        isOpen: { false }, show: {}, hide: {}, toggle: {}
    )
}

extension EnvironmentValues {
    var inspector: InspectorController {
        get { self[InspectorControllerKey.self] }
        set { self[InspectorControllerKey.self] = newValue }
    }
}

final class InspectorToggleModel: ObservableObject {
    @Published var isOpen: Bool = true  // when this toolbar is visible, the inspector exists → start true
    private var bag = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: InspectorBus.show)
            .sink { [weak self] _ in self?.isOpen = true }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: InspectorBus.hide)
            .sink { [weak self] _ in self?.isOpen = false }
            .store(in: &bag)
    }
}

struct InspectorToggleToolbarItems: ToolbarContent {
    @StateObject private var model = InspectorToggleModel()

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                if model.isOpen { InspectorBus.hideNow() } else { InspectorBus.showNow() }
            } label: {
                Label(model.isOpen ? "Hide Inspector" : "Show Inspector",
                      systemImage: model.isOpen ? "sidebar.trailing" : "sidebar.leading")
            }
            .help(model.isOpen ? "Hide Inspector" : "Show Inspector")
        }
    }
}

