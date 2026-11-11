//
//  SignInText.swift
//  CloudDoorKit
//
//  The wording around signing in, kept here so that it can be tested.
//

import Foundation

public enum SignInText {
    public static let successTitle = "Saved and working"

    public static func successDetail(account: String) -> String {
        "Signed in as \(account). CloudDoor reached the server."
    }

    // MARK: After a failed attempt
    //
    // A failed attempt never changes the saved account, because new details are only saved once the server has
    // accepted them. These say which account that leaves in use.

    public static let stillSignedInTitle = "You're still signed in"

    /// - Parameter account: The email of the account that is still saved.
    public static func stillSignedInDetail(account: String) -> String {
        guard !account.isEmpty else {
            return "Your previous account is unchanged and keeps working."
        }
        return "Your previous account, \(account), is unchanged and keeps working."
    }

    public static let notSignedInTitle = "You're not signed in yet"
    public static let notSignedInDetail = "Nothing was saved."

    // MARK: Clearing the saved account

    public static let clearButton = "Clear Credentials"
    public static let clearConfirmationTitle = "Clear saved credentials?"
    public static let clearConfirmationMessage = "This signs you out and removes the saved account from this iPhone. Your doors disappear until you sign in again."
}
