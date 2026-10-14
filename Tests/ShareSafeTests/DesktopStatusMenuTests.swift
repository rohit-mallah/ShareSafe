import AppKit
import Testing
@testable import ShareSafe

@MainActor
struct DesktopStatusMenuTests {
    private func menu(count: Int = 0, editing: Bool = false, emergency: Bool = false,
                      error: String? = nil,
                      action: @escaping (DesktopStatusAction) -> Void = { _ in }) -> DesktopStatusMenu {
        DesktopStatusMenu(regionCount: count, isEditing: editing, emergencyCovered: emergency,
                          error: error, shortcutWarning: nil, performAction: action)
    }

    private func item(_ action: DesktopStatusAction, in controller: DesktopStatusMenu) throws -> NSMenuItem {
        try #require(controller.menu.items.first { ($0.representedObject as? String) == action.rawValue })
    }

    @Test func emptySessionOffersSelectionWithoutUnavailableAreaActions() throws {
        let controller = menu()
        #expect(try item(.selectArea, in: controller).isEnabled)
        for action in [DesktopStatusAction.editAreas, .undo, .clear] {
            #expect(try !item(action, in: controller).isEnabled)
        }
        #expect(controller.menu.items.contains { $0.title == "Share your entire screen in your meeting" })
        #expect(!controller.menu.items.contains { $0.title.contains("Protected View") || $0.title.contains("Add window") })
    }

    @Test func existingAreasCanBeEditedUndoneAndCleared() throws {
        let controller = menu(count: 2, editing: true)
        for action in [DesktopStatusAction.editAreas, .undo, .clear] {
            #expect(try item(action, in: controller).isEnabled)
        }
        #expect(try item(.editAreas, in: controller).title.hasPrefix("Finish editing"))
        #expect(try item(.removeSelected, in: controller).isEnabled)
        #expect(controller.menu.items.contains { $0.title == "2 areas hidden" })
    }

    @Test func emergencyMenuKeepsRecoveryAvailableWithoutRemovingOrdinaryAreas() throws {
        let controller = menu(count: 2, emergency: true, error: "Capture stopped")
        for action in [DesktopStatusAction.selectArea, .editAreas, .undo, .clear] {
            #expect(try !item(action, in: controller).isEnabled)
        }
        #expect(try item(.toggleEmergency, in: controller).isEnabled)
        #expect(try item(.toggleEmergency, in: controller).title.hasPrefix("Restore screen"))
        #expect(try item(.quit, in: controller).isEnabled)
    }

    @Test func displayChangeShowsReviewInstructionWithoutCapturePermissionControls() throws {
        let controller = menu(count: 1, error: "Screen changed: internal diagnostic detail")
        #expect(controller.menu.items.contains { $0.title == "Review your areas after the screen change" })
        #expect(!controller.menu.items.contains { $0.title.contains("Screen Recording") || $0.title.contains("Retry blur") })
        #expect(!controller.menu.items.contains { $0.title.contains("internal diagnostic") })
    }

    @Test func menuActionsReachTheOwningController() throws {
        var invoked: [DesktopStatusAction] = []
        let controller = menu(count: 1) { invoked.append($0) }
        for action in [DesktopStatusAction.selectArea, .undo, .clear, .toggleEmergency, .quit] {
            let selected = try item(action, in: controller)
            let target = try #require(selected.target as? NSObject)
            let selector = try #require(selected.action)
            #expect(target.responds(to: selector))
            target.perform(selector, with: selected)
        }
        #expect(invoked == [.selectArea, .undo, .clear, .toggleEmergency, .quit])
    }

    @Test func menuShortcutLabelsMatchTheRegisteredShortcutCatalog() throws {
        let controller = menu(count: 2)
        for shortcut in DesktopShortcut.all {
            #expect(try item(shortcut.action, in: controller).title.hasSuffix(shortcut.label))
        }
        #expect(Set(DesktopShortcut.all.map(\.id)).count == DesktopShortcut.all.count)
        #expect(Set(DesktopShortcut.all.map(\.keyCode)).count == DesktopShortcut.all.count)
        #expect(Set(DesktopShortcut.all.map(\.action)) == [.selectArea, .editAreas, .undo, .clear, .toggleEmergency])
    }

    @Test func hiddenWindowsKeepUndoAndClearAvailableWithoutOfferingInvisibleEdits() throws {
        let controller = DesktopStatusMenu(regionCount: 2, isEditing: false, emergencyCovered: false,
            error: nil, shortcutWarning: nil, visibleRegionCount: 0, performAction: { _ in })
        #expect(try !item(.editAreas, in: controller).isEnabled)
        #expect(try item(.undo, in: controller).isEnabled)
        #expect(try item(.clear, in: controller).isEnabled)
        #expect(controller.menu.items.contains { $0.title == "0 areas hidden" })
        #expect(controller.menu.items.contains { $0.title == "2 saved on their windows" })
    }

    @Test func unsupportedSelectionShowsTheRelevantRecoveryInstruction() {
        let controller = menu(error: "Start your drag inside an app window. The area must overlap that window.")
        #expect(controller.menu.items.contains { $0.title == "Start your drag inside an app window" })
    }
}
