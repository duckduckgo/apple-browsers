//
//  main.swift
//  BrowserServicesKit
//
//  Created by admin on 4/7/25.
//

import XCTest

class TestObserver: NSObject, XCTestObservation {
    func testBundleWillStart(_ testBundle: Bundle) {
        print("Test bundle will start: \(testBundle.bundlePath)")
        // Set up your observer or any global state here
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        print("Test bundle did finish: \(testBundle.bundlePath)")
    }
}

// Register the observer
let observer = TestObserver()
XCTestObservationCenter.shared.addTestObserver(observer)

// Run the tests
XCTMain([
    testCase(MyTests.allTests) // Replace with your test cases
])
