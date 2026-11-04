//
//  InspectorAccessibilityTests.swift
//  CinematicCoreMacOSTests
//
//  A11Y-INSPECTOR: the Inspector's open/close controls have spoken names
//  instead of "option" (the ⌥ face) or a chevron symbol name.
//

import Testing
@testable import Alfie

struct InspectorAccessibilityTests {
    @Test func handleAndCloseButtonSayWhatTheyDo() {
        #expect(InspectorHandle.accessibilityLabel(isOpen: false) == "Open Inspector")
        #expect(InspectorHandle.accessibilityLabel(isOpen: true) == "Close Inspector")
    }
}
