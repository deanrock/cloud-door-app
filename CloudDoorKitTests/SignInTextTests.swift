//
//  SignInTextTests.swift
//  CloudDoorKitTests
//

import Testing
@testable import CloudDoorKit

struct SignInTextTests {
    @Test func successNamesTheAccountAndSaysTheServerWasReached() {
        #expect(SignInText.successTitle == "Saved and working")
        #expect(SignInText.successDetail(account: "anna@example.com")
                == "Signed in as anna@example.com. CloudDoor reached the server.")
    }

    @Test func aFailedAttemptSaysThePreviousAccountIsStillSignedIn() {
        #expect(SignInText.stillSignedInTitle == "You're still signed in")
        #expect(SignInText.stillSignedInDetail(account: "anna@example.com")
                == "Your previous account, anna@example.com, is unchanged and keeps working.")
    }

    @Test func aPreviousAccountWithoutAnEmailIsStillMentioned() {
        #expect(SignInText.stillSignedInDetail(account: "")
                == "Your previous account is unchanged and keeps working.")
    }

    @Test func aFailedFirstAttemptSaysNobodyIsSignedIn() {
        #expect(SignInText.notSignedInTitle == "You're not signed in yet")
        #expect(SignInText.notSignedInDetail == "Nothing was saved.")
    }

    @Test func clearingExplainsWhatWillHappen() {
        #expect(SignInText.clearButton == "Clear Credentials")
        #expect(SignInText.clearConfirmationMessage.contains("signs you out"))
        #expect(SignInText.clearConfirmationMessage.contains("doors disappear"))
    }
}
