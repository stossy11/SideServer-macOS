//
//  AppleIDAuthenticationAlert.swift
//  AltServer
//
//  Created by royal on 17/12/2022.
//

import AppKit

// MARK: - AppleIDAuthenticationAlert

final class AppleIDAuthenticationAlert: NSAlert {

	private let appleIDTextField: NSTextField
	private let passwordTextField: NSSecureTextField

	var appleIDValue: String {
		get { appleIDTextField.stringValue }
	}

	var passwordValue: String {
		get { passwordTextField.stringValue }
	}

	override init() {
		let textFieldSize = NSSize(width: 300, height: 22)

		let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: textFieldSize.width, height: textFieldSize.height * 2))
		stackView.orientation = .vertical
		stackView.distribution = .equalSpacing
		stackView.spacing = 0

		appleIDTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: textFieldSize.width, height: textFieldSize.height))
		appleIDTextField.translatesAutoresizingMaskIntoConstraints = false
		appleIDTextField.placeholderString = NSLocalizedString("Apple ID", comment: "")
		stackView.addArrangedSubview(appleIDTextField)

		passwordTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: textFieldSize.width, height: textFieldSize.height))
		passwordTextField.translatesAutoresizingMaskIntoConstraints = false
		passwordTextField.placeholderString = NSLocalizedString("Password", comment: "")
		stackView.addArrangedSubview(passwordTextField)

		appleIDTextField.nextKeyView = passwordTextField

		super.init()

		appleIDTextField.delegate = self
		passwordTextField.delegate = self

		messageText = NSLocalizedString("Please enter your Apple ID and password.", comment: "")
		informativeText = NSLocalizedString("Your Apple ID and password will be saved in the Keychain and will be sent only to Apple servers.", comment: "")
		accessoryView = stackView

		window.initialFirstResponder = appleIDTextField

		addButton(withTitle: NSLocalizedString("Continue", comment: ""))
		addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

		validateTextFields()
	}

	/// Displays the alert modally, and returns a `Bool` saying whether the user did press "Continue".
	func display() -> Bool {
		let result = runModal()
		NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
		return result == .alertFirstButtonReturn
	}
}

// MARK: - AppleIDAuthenticationAlert+NSTextFieldDelegate

extension AppleIDAuthenticationAlert: NSTextFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		validateTextFields()
	}
}

// MARK: - AppleIDAuthenticationAlert+Private

private extension AppleIDAuthenticationAlert {
	func validateTextFields() {
		let isAppleIDTextFieldValid = !appleIDValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		let isPasswordTextFieldValid = !passwordValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		buttons.first?.isEnabled = isAppleIDTextFieldValid && isPasswordTextFieldValid
	}
}
