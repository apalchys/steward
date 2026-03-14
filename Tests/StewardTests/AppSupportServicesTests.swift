import ServiceManagement
import XCTest
@testable import Steward

@MainActor
final class AppSupportServicesTests: XCTestCase {
    func testLaunchAtLoginStatusMappingMatchesServiceManagement() {
        XCTAssertEqual(AppSystemServices.launchAtLoginStatus(from: .notRegistered), .notRegistered)
        XCTAssertEqual(AppSystemServices.launchAtLoginStatus(from: .enabled), .enabled)
        XCTAssertEqual(AppSystemServices.launchAtLoginStatus(from: .requiresApproval), .requiresApproval)
        XCTAssertEqual(AppSystemServices.launchAtLoginStatus(from: .notFound), .notFound)
    }

    func testLaunchAtLoginErrorMappingCategorizesKnownCodes() {
        XCTAssertEqual(
            AppSystemServices.launchAtLoginError(from: NSError(domain: SMAppServiceErrorDomain, code: kSMErrorLaunchDeniedByUser)),
            .requiresApproval
        )
        XCTAssertEqual(
            AppSystemServices.launchAtLoginError(from: NSError(domain: SMAppServiceErrorDomain, code: kSMErrorInvalidSignature)),
            .invalidSignature
        )
        XCTAssertEqual(
            AppSystemServices.launchAtLoginError(from: NSError(domain: SMAppServiceErrorDomain, code: kSMErrorServiceUnavailable)),
            .serviceUnavailable
        )
        XCTAssertEqual(
            AppSystemServices.launchAtLoginError(from: NSError(domain: SMAppServiceErrorDomain, code: kSMErrorInternalFailure)),
            .unknown
        )
    }

    func testIdempotentLaunchAtLoginErrorsAreRecognized() {
        XCTAssertTrue(
            AppSystemServices.isIdempotentLaunchAtLoginError(
                NSError(domain: SMAppServiceErrorDomain, code: kSMErrorAlreadyRegistered),
                isEnabled: true
            )
        )
        XCTAssertTrue(
            AppSystemServices.isIdempotentLaunchAtLoginError(
                NSError(domain: SMAppServiceErrorDomain, code: kSMErrorJobNotFound),
                isEnabled: false
            )
        )
        XCTAssertFalse(
            AppSystemServices.isIdempotentLaunchAtLoginError(
                NSError(domain: SMAppServiceErrorDomain, code: kSMErrorAlreadyRegistered),
                isEnabled: false
            )
        )
    }

    func testLiveOpenLoginItemsSettingsUsesProvidedAction() {
        var callCount = 0
        let services = AppSystemServices.live(openLoginItemsSettingsAction: { callCount += 1 })

        services.openLoginItemsSettings()

        XCTAssertEqual(callCount, 1)
    }
}
