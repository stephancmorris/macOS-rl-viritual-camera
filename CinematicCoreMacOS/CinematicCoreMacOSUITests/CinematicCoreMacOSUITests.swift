//
//  CinematicCoreMacOSUITests.swift
//  CinematicCoreMacOSUITests
//
//  Created by Stephan Morris on 2/2/2026.
//

import XCTest

final class CinematicCoreMacOSUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
