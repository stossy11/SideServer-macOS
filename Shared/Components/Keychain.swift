//
//  Keychain.swift
//  AltServer
//
//  Created by royal on 17/12/2022.
//

import Foundation
import KeychainAccess

// MARK: - Keychain

struct Keychain {
	static let shared = Keychain()

	private let keychain = KeychainAccess.Keychain(accessGroup: "\(Bundle.main.appIdentifierPrefix ?? "")group.\(Bundle.main.bundleIdentifier ?? "")").synchronizable(true)

	private init() {}

	public func setValue(_ value: String?, for key: Keychain.Key) throws {
		if let value {
			try keychain.set(value, key: key.rawValue)
		} else {
			try keychain.remove(key.rawValue)
		}
	}

	public func getValue(for key: Keychain.Key) throws -> String {
		let value = try keychain.getString(key.rawValue)
		guard let value else {
			throw KeychainError.noValueForKey
		}
		return value
	}
}

// MARK: - Keychain+Key

extension Keychain {
	enum Key: String {
		case appleIDEmail = "AppleIDEmail"
		case appleIDPassword = "AppleIDPassword"
	}
}

// MARK: - Keychain+Errors

extension Keychain {
	enum KeychainError: Error {
		case noValueForKey
	}
}
