//
//  ErrorDescriptionTests.swift
//  CloudDoorKitTests
//

import Foundation
import Testing
@testable import CloudDoorKit

struct ErrorDescriptionTests {
    func describe(_ error: Error) -> ErrorDescription {
        ErrorDescription(error: error)
    }

    // MARK: Server errors

    @Test(arguments: [401, 403])
    func rejectedAccountsPointToSettings(status: Int) {
        let description = describe(ApiError.http(status: status, body: ""))

        #expect(description.message == "The server didn't accept your account. Check your email and password in Settings.")
    }

    @Test func missingPagesPointToTheServerAddress() {
        #expect(describe(ApiError.http(status: 404, body: "")).message.contains("server address"))
    }

    @Test(arguments: [500, 502, 503, 599])
    func serverProblemsAreSaidToBeTemporary(status: Int) {
        #expect(describe(ApiError.http(status: status, body: "")).message
                == "The server had a problem (error \(status)). Try again in a moment.")
    }

    @Test func otherStatusCodesAreStillMentioned() {
        #expect(describe(ApiError.http(status: 418, body: "")).message.contains("418"))
    }

    @Test func detailsKeepTheStatusAndTheServerReply() {
        let details = describe(ApiError.http(status: 500, body: "{\"error\":\"db down\"}")).details

        #expect(details == "HTTP 500\n{\"error\":\"db down\"}")
    }

    @Test func detailsAreShortWhenTheReplyIsEmpty() {
        #expect(describe(ApiError.http(status: 502, body: "")).details == "HTTP 502")
    }

    @Test func repliesAreCutToAReadableLength() {
        let long = Data(String(repeating: "x", count: 5_000).utf8)

        #expect(ApiError.excerpt(of: long).count == 500)
    }

    @Test func repliesWithSurroundingWhitespaceAreTrimmed() {
        #expect(ApiError.excerpt(of: Data("  oops \n".utf8)) == "oops")
    }

    @Test func serverMessagesAreShownAsTheyAre() {
        let description = describe(ApiError.runtimeError("The user name or password is incorrect."))

        #expect(description.message == "The user name or password is incorrect.")
        #expect(description.details == "Server message: The user name or password is incorrect.")
    }

    // MARK: Network errors

    @Test func offlineHasItsOwnIcon() {
        let description = describe(URLError(.notConnectedToInternet))

        #expect(description.symbol == "wifi.slash")
        #expect(description.message.contains("offline"))
    }

    @Test func timeoutsSuggestTryingAgain() {
        #expect(describe(URLError(.timedOut)).message == "The server took too long to respond. Please try again.")
    }

    @Test(arguments: [URLError.Code.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed])
    func unreachableServersPointToTheAddress(code: URLError.Code) {
        #expect(describe(URLError(code)).message.contains("server address"))
    }

    @Test func networkDetailsIncludeTheSystemErrorCode() {
        let details = describe(URLError(.timedOut)).details

        #expect(details?.hasPrefix("URLError -1001") == true)
    }

    // MARK: Other errors

    @Test func unexpectedRepliesAreExplained() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad json"))
        let description = describe(error)

        #expect(description.message.contains("doesn't understand"))
        #expect(description.details?.contains("bad json") == true)
    }

    @Test func keychainFailuresKeepTheirStatusCode() {
        let description = describe(SecretStoreError(status: -34018))

        #expect(description.details == "Keychain status -34018")
        #expect(description.message.contains("keychain"))
    }

    @Test func unknownErrorsStillShowSomethingUsefulInDetails() {
        struct Odd: Error {}
        let description = describe(Odd())

        #expect(description.details?.contains("Odd") == true)
    }

    // MARK: Door errors

    @Test func tooFarKeepsTheNumbersInDetails() {
        let description = describe(DoorError.tooFar(name: "Gate", distance: 120, radius: 50))

        #expect(description.details == "Distance 120m, allowed radius 50m")
        #expect(description.action == nil)
    }

    @Test func missingLocationOffersToOpenSettings() {
        let description = describe(DoorError.locationUnknown)

        #expect(description.action == .openLocationSettings)
        #expect(description.symbol == "location.slash.fill")
    }

    @Test func otherDoorErrorsOfferNoAction() {
        #expect(describe(DoorError.notConfigured).action == nil)
        #expect(describe(DoorError.doorNotFound).action == nil)
    }

    @Test func locationMessageTellsWhatToDo() {
        #expect(describe(DoorError.locationUnknown).message
                == "CloudDoor can't find your location. Allow location access in Settings and try again.")
    }
}

struct ShortMessageTests {
    func short(_ error: Error) -> String {
        ErrorDescription(error: error).shortMessage
    }

    @Test func tooFarShowsBothNumbers() {
        #expect(short(DoorError.tooFar(name: "Gate", distance: 120, radius: 80)) == "Too far: 120m away, limit 80m")
    }

    @Test func doorProblemsHaveShortNames() {
        #expect(short(DoorError.locationUnknown) == "Location unavailable")
        #expect(short(DoorError.notConfigured) == "Not signed in")
        #expect(short(DoorError.doorNotFound) == "Door not found")
    }

    @Test func networkProblemsHaveShortNames() {
        #expect(short(URLError(.notConnectedToInternet)) == "Offline")
        #expect(short(URLError(.timedOut)) == "Timed out")
        #expect(short(URLError(.cannotFindHost)) == "Can't reach the server")
        #expect(short(URLError(.badURL)) == "Network error")
    }

    @Test func serverProblemsHaveShortNames() {
        #expect(short(ApiError.http(status: 401, body: "")) == "Account not accepted")
        #expect(short(ApiError.http(status: 404, body: "")) == "Server address not found")
        #expect(short(ApiError.http(status: 503, body: "")) == "Server error 503")
        #expect(short(ApiError.http(status: 418, body: "")) == "Error 418")
    }

    @Test func serverMessagesAreUsedAsTheyAre() {
        #expect(short(ApiError.runtimeError("Wrong password")) == "Wrong password")
    }

    @Test func everythingElseSaysSomethingWentWrong() {
        struct Odd: Error {}
        #expect(short(Odd()) == "Something went wrong")
    }
}

struct AccountRejectionTests {
    @Test func theServerRefusingTheAccountIsARejection() {
        #expect(ApiError.accountRejected("The user name or password is incorrect.").isAccountRejection)
        #expect(ApiError.http(status: 401, body: "").isAccountRejection)
        #expect(ApiError.http(status: 403, body: "").isAccountRejection)
    }

    /// Being offline or hitting a broken server says nothing about the account, so it must not sign anyone out.
    @Test func otherFailuresAreNotARejection() {
        #expect(!ApiError.http(status: 500, body: "").isAccountRejection)
        #expect(!ApiError.http(status: 404, body: "").isAccountRejection)
        #expect(!ApiError.runtimeError("The server didn't send a valid response.").isAccountRejection)
    }

    /// The server answers with a code like "msgInvalidLogin"; the person reads a sentence and the code is a detail.
    @Test func aRejectionIsExplainedInPlainWordsAndKeepsTheServersCode() {
        let description = ErrorDescription(error: ApiError.accountRejected("msgInvalidLogin"))

        #expect(description.message == "The server didn't accept your account. Check your email and password in Settings.")
        #expect(!description.message.contains("msgInvalidLogin"))
        #expect(!description.shortMessage.contains("msgInvalidLogin"))
        #expect(description.shortMessage == "Account not accepted")
        #expect(description.details == "Server message: msgInvalidLogin")
    }

    @Test func rejectionsAreReadableInSiriToo() {
        let failure = DoorIntentError.wrap(ApiError.accountRejected("msgInvalidLogin")) as? DoorIntentFailure

        #expect(failure?.message == "The server didn't accept your account. Check your email and password in Settings.")
    }
}
