import AppKit
import Combine
import SwiftUI

struct MenuBarInstaller: View {
    @ObservedObject var controller: MenuBarController
    @EnvironmentObject private var eventKit: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                controller.configure(eventKit: eventKit, store: store, settings: settings)
            }
    }
}

@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?
    private var configured = false

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true

        cancellable = settings.$menuBarEnabled
            .removeDuplicates()
            .sink { [weak self, weak eventKit, weak store, weak settings] enabled in
                guard let self, let eventKit, let store, let settings else { return }
                self.setVisible(enabled, eventKit: eventKit, store: store, settings: settings)
            }

        setVisible(settings.menuBarEnabled, eventKit: eventKit, store: store, settings: settings)
    }

    private func setVisible(_ visible: Bool,
                            eventKit: EventKitService,
                            store: ProjectStore,
                            settings: AppSettings) {
        if visible {
            install(eventKit: eventKit, store: store, settings: settings)
        } else {
            popover?.close()
            popover = nil
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func install(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.templateImage()
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 220)
        popover.contentViewController = NSHostingController(
            rootView: QuickCaptureView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func templateImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        if let url = Bundle.main.url(forResource: "FacetXMenuBarTemplate", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        if let url = Bundle.main.url(forResource: "FacetXMenuBarTemplate@2x", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        if image.representations.isEmpty,
           let fallback = NSImage(systemSymbolName: "diamond", accessibilityDescription: "FacetX") {
            fallback.isTemplate = true
            fallback.size = NSSize(width: 18, height: 18)
            return fallback
        }
        image.isTemplate = true
        return image
    }
}
