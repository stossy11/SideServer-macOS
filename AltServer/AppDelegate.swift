//
//  AppDelegate.swift
//  AltServer
//
//  Created by Riley Testut on 5/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Cocoa
import UserNotifications

import AltSign

import LaunchAtLogin
import Sparkle

private let altstoreAppURL = URL(string: "https://github.com/SideStore/SideStore/releases/download/0.1.1/SideStore.ipa")!

extension ALTDevice: MenuDisplayable {}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    
    private var statusItem: NSStatusItem?
    
    private var connectedDevices = [ALTDevice]()
    
    private weak var authenticationAlert: NSAlert?
    
    @IBOutlet private var appMenu: NSMenu!
    @IBOutlet private var connectedDevicesMenu: NSMenu!
    @IBOutlet private var sideloadIPAConnectedDevicesMenu: NSMenu!
    @IBOutlet private var enableJITMenu: NSMenu!
    
    @IBOutlet private var launchAtLoginMenuItem: NSMenuItem!
    @IBOutlet private var sideloadAppMenuItem: NSMenuItem!
    @IBOutlet private var installAltStoreMenuItem: NSMenuItem!
	@IBOutlet private var logInMenuItem: NSMenuItem!
    
    private var connectedDevicesMenuController: MenuController<ALTDevice>!
    private var sideloadIPAConnectedDevicesMenuController: MenuController<ALTDevice>!
    private var enableJITMenuController: MenuController<ALTDevice>!
    
    private var _jitAppListMenuControllers = [AnyObject]()
        
    func applicationDidFinishLaunching(_ aNotification: Notification)
    {
        UserDefaults.standard.registerDefaults()
        
        UNUserNotificationCenter.current().delegate = self
        
        ServerConnectionManager.shared.start()
        ALTDeviceManager.shared.start()
        
        #if STAGING
        let feedURL: String = Bundle.main.infoDictionary!["SUFeedURL"]! as! String
        #else
        let feedURL: String  = Bundle.main.infoDictionary!["SUFeedURL"]! as! String
        #endif
        
        SUUpdater.shared().feedURL = URL(string: feedURL)

        let item = NSStatusBar.system.statusItem(withLength: -1)
        item.menu = self.appMenu
        item.button?.image = NSImage(named: "MenuBarIcon") 
        self.statusItem = item
        
        self.appMenu.delegate = self
        
        self.sideloadAppMenuItem.keyEquivalentModifierMask = .option
        self.sideloadAppMenuItem.isAlternate = true
        
        let placeholder = NSLocalizedString("No Connected Devices", comment: "")
        
        self.connectedDevicesMenuController = MenuController<ALTDevice>(menu: self.connectedDevicesMenu, items: [])
        self.connectedDevicesMenuController.placeholder = placeholder
        self.connectedDevicesMenuController.action = { [weak self] device in
            self?.installAltStore(to: device)
        }
        
        self.sideloadIPAConnectedDevicesMenuController = MenuController<ALTDevice>(menu: self.sideloadIPAConnectedDevicesMenu, items: [])
        self.sideloadIPAConnectedDevicesMenuController.placeholder = placeholder
        self.sideloadIPAConnectedDevicesMenuController.action = { [weak self] device in
            self?.sideloadIPA(to: device)
        }
        
        self.enableJITMenuController = MenuController<ALTDevice>(menu: self.enableJITMenu, items: [])
        self.enableJITMenuController.placeholder = placeholder
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { (success, error) in
            guard success else { return }
            
            if !UserDefaults.standard.didPresentInitialNotification
            {
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("SideServer Running", comment: "")
                content.body = NSLocalizedString("SideServer runs in the background as a menu bar app listening for SideStore.", comment: "")
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
                
                UserDefaults.standard.didPresentInitialNotification = true
            }
        }
        
		setupLoginMenuItem()
    }

    func applicationWillTerminate(_ aNotification: Notification)
    {
        // Insert code here to tear down your application
    }
}

private extension AppDelegate
{
    @objc func installAltStore(to device: ALTDevice)
    {
        self.installApplication(at: altstoreAppURL, to: device)
    }
    
    @objc func sideloadIPA(to device: ALTDevice)
    {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedFileTypes = ["ipa"]
        openPanel.begin { (response) in
            guard let fileURL = openPanel.url, response == .OK else { return }
            self.installApplication(at: fileURL, to: device)
        }
    }
    
    func enableJIT(for app: InstalledApp, on device: ALTDevice)
    {
        func finish(_ result: Result<Void, Error>)
        {
            DispatchQueue.main.async {
                switch result
                {
                case .failure(let error):
                    self.showErrorAlert(error: error, localizedFailure: String(format: NSLocalizedString("JIT compilation could not be enabled for %@.", comment: ""), app.name))
                    
                case .success:
                    let alert = NSAlert()
                    alert.messageText = String(format: NSLocalizedString("Successfully enabled JIT for %@.", comment: ""), app.name)
                    alert.informativeText = String(format: NSLocalizedString("JIT will remain enabled until you quit the app. You can now disconnect %@ from your computer.", comment: ""), device.name)
                    alert.runModal()
                }
            }
        }
        
        ALTDeviceManager.shared.prepare(device) { (result) in
            switch result
            {
            case .failure(let error as NSError): return finish(.failure(error))
            case .success:
                ALTDeviceManager.shared.startDebugConnection(to: device) { (connection, error) in
                    guard let connection = connection else {
                        return finish(.failure(error! as NSError))
                    }
                    
                    connection.enableUnsignedCodeExecutionForProcess(withName: app.executableName) { (success, error) in
                        guard success else {
                            return finish(.failure(error!))
                        }
                        
                        finish(.success(()))
                    }
                }
            }
        }
    }
    
    func installApplication(at url: URL, to device: ALTDevice)
    {
		let username: String
		let password: String

		if let _username = try? Keychain.shared.getValue(for: .appleIDEmail),
		   let _password = try? Keychain.shared.getValue(for: .appleIDPassword) {
			username = _username
			password = _password
		} else {
			let alert = AppleIDAuthenticationAlert()
			self.authenticationAlert = alert

			NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

			let didTapContinue = alert.display()
			guard didTapContinue else { return }

			username = alert.appleIDValue.trimmingCharacters(in: .whitespacesAndNewlines)
			password = alert.passwordValue.trimmingCharacters(in: .whitespacesAndNewlines)

			do {
				try Keychain.shared.setValue(username.isEmpty ? nil : username, for: .appleIDEmail)
				try Keychain.shared.setValue(password.isEmpty ? nil : password, for: .appleIDPassword)
			} catch {
				print("AppleID Auth: Error saving credentials: \(error)")
			}
		}
        
        func finish(_ result: Result<ALTApplication, Error>)
        {
            switch result
            {
            case .success(let application):
                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString("Installation Succeeded", comment: "")
                content.body = String(format: NSLocalizedString("%@ was successfully installed on %@.", comment: ""), application.name, device.name)
                
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
                
            case .failure(InstallError.cancelled), .failure(ALTAppleAPIError.requiresTwoFactorAuthentication):
                // Ignore
                break
                
            case .failure(let error):
                DispatchQueue.main.async {
                    self.showErrorAlert(error: error, localizedFailure: String(format: NSLocalizedString("Could not install app to %@.", comment: ""), device.name))
                }
            }
        }

            ALTDeviceManager.shared.installApplication(at: url, to: device, appleID: username, password: password, completion: finish(_:))
        
    }
    
    func showErrorAlert(error: Error, localizedFailure: String)
    {
        let nsError = error as NSError
        
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = localizedFailure
        
        var messageComponents = [String]()
        
        let separator: String
        switch error
        {
        case ALTServerError.maximumFreeAppLimitReached: separator = "\n\n"
        default: separator = " "
        }
        
        if let errorFailure = nsError.localizedFailure
        {
            if let debugDescription = nsError.localizedDebugDescription
            {
                alert.messageText = errorFailure
                messageComponents.append(debugDescription)
            }
            else if let failureReason = nsError.localizedFailureReason
            {
                if nsError.localizedDescription.starts(with: errorFailure)
                {
                    alert.messageText = errorFailure
                    messageComponents.append(failureReason)
                }
                else
                {
                    alert.messageText = errorFailure
                    messageComponents.append(nsError.localizedDescription)
                }
            }
            else
            {
                // No failure reason given.
                
                if nsError.localizedDescription.starts(with: errorFailure)
                {
                    // No need to duplicate errorFailure in both title and message.
                    alert.messageText = localizedFailure
                    messageComponents.append(nsError.localizedDescription)
                }
                else
                {
                    alert.messageText = errorFailure
                    messageComponents.append(nsError.localizedDescription)
                }
            }
        }
        else
        {
            alert.messageText = localizedFailure
            
            if let debugDescription = nsError.localizedDebugDescription
            {
                messageComponents.append(debugDescription)
            }
            else
            {
                messageComponents.append(nsError.localizedDescription)
            }
        }
        
        if let recoverySuggestion = nsError.localizedRecoverySuggestion
        {
            messageComponents.append(recoverySuggestion)
        }
        
        let informativeText = messageComponents.joined(separator: separator)
        alert.informativeText = informativeText
        
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)

        alert.runModal()
    }
    
    @objc func toggleLaunchAtLogin(_ item: NSMenuItem)
    {
        LaunchAtLogin.isEnabled.toggle()
    }

}

// MARK: - AppDelegate+loginMenuItem

private extension AppDelegate {
	private func setupLoginMenuItem() {
		do {
			let email = try Keychain.shared.getValue(for: .appleIDEmail)
			logInMenuItem.title = "Log out (\(email))"
			logInMenuItem.action = #selector(logoutFromAppleID)
		} catch {
			print("Error getting stored AppleID credentials: \(error)")
			logInMenuItem.title = "Save Apple ID Login..."
			logInMenuItem.action = #selector(loginToAppleID)
		}
	}

	@objc private func loginToAppleID() {
		let alert = AppleIDAuthenticationAlert()

		NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
		let didTapContinue = alert.display()
		guard didTapContinue else { return }

		let username = alert.appleIDValue.trimmingCharacters(in: .whitespacesAndNewlines)
		let password = alert.passwordValue.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !username.isEmpty && !password.isEmpty else {
			print("AppleID Auth: Username and/or password was empty.")
			return
		}

		do {
			try Keychain.shared.setValue(username, for: .appleIDEmail)
			try Keychain.shared.setValue(password, for: .appleIDPassword)
		} catch {
			let errorAlert = NSAlert(error: error)
			NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
			errorAlert.runModal()
			
			print("AppleID Auth: Error saving credentials: \(error)")
		}

		setupLoginMenuItem()
	}

	@objc private func logoutFromAppleID() {
		print("Removing AppleID credentials!")
		try? Keychain.shared.setValue(nil, for: .appleIDEmail)
		try? Keychain.shared.setValue(nil, for: .appleIDPassword)
		setupLoginMenuItem()
	}
}

extension AppDelegate: NSMenuDelegate
{
    func menuWillOpen(_ menu: NSMenu)
    {
        guard menu == self.appMenu else { return }
        
        // Clear any cached _jitAppListMenuControllers.
        self._jitAppListMenuControllers.removeAll()

        self.connectedDevices = ALTDeviceManager.shared.availableDevices
        
        self.connectedDevicesMenuController.items = self.connectedDevices
        self.sideloadIPAConnectedDevicesMenuController.items = self.connectedDevices
        self.enableJITMenuController.items = self.connectedDevices

        self.launchAtLoginMenuItem.target = self
        self.launchAtLoginMenuItem.action = #selector(AppDelegate.toggleLaunchAtLogin(_:))
        self.launchAtLoginMenuItem.state = LaunchAtLogin.isEnabled ? .on : .off
        
        // Need to re-set this every time menu appears so we can refresh device app list.
        self.enableJITMenuController.submenuHandler = { [weak self] device in
            let submenu = NSMenu(title: NSLocalizedString("Sideloaded Apps", comment: ""))
            
            guard let `self` = self else { return submenu }

            let submenuController = MenuController<InstalledApp>(menu: submenu, items: [])
            submenuController.placeholder = NSLocalizedString("Loading...", comment: "")
            submenuController.action = { [weak self] (appInfo) in
                self?.enableJIT(for: appInfo, on: device)
            }
            
            // Keep strong reference
            self._jitAppListMenuControllers.append(submenuController)

            ALTDeviceManager.shared.fetchInstalledApps(on: device) { (installedApps, error) in
                DispatchQueue.main.async {
                    guard let installedApps = installedApps else {
                        print("Failed to fetch installed apps from \(device).", error!)
                        submenuController.placeholder = error?.localizedDescription
                        return
                    }
                    
                    print("Fetched \(installedApps.count) apps for \(device).")
                    
                    let sortedApps = installedApps.sorted { (app1, app2) in
                        if app1.name == app2.name
                        {
                            return app1.bundleIdentifier < app2.bundleIdentifier
                        }
                        else
                        {
                            return app1.name < app2.name
                        }
                    }
                    
                    submenuController.items = sortedApps
                    
                    if submenuController.items.isEmpty
                    {
                        submenuController.placeholder = NSLocalizedString("No Sideloaded Apps", comment: "")
                    }
                }
            }

            return submenu
        }
    }
    
    func menuDidClose(_ menu: NSMenu)
    {
        guard menu == self.appMenu else { return }
        
        // Clearing _jitAppListMenuControllers now prevents action handler from being called.
        // self._jitAppListMenuControllers = []
        
        // Set `submenuHandler` to nil to prevent prematurely fetching installed apps in menuWillOpen(_:)
        // when assigning self.connectedDevices to `items` (which implicitly calls `submenuHandler`)
        self.enableJITMenuController.submenuHandler = nil
    }
    
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?)
    {
        guard menu == self.appMenu else { return }
        
        // The submenu won't update correctly if the user holds/releases
        // the Option key while the submenu is visible.
        // Workaround: temporarily set submenu to nil to dismiss it,
        // which will then cause the correct submenu to appear.
        
        let previousItem: NSMenuItem
        switch item
        {
        case self.sideloadAppMenuItem:
            previousItem = self.installAltStoreMenuItem
        case self.installAltStoreMenuItem:
            previousItem = self.sideloadAppMenuItem
        default: return
        }

        let submenu = previousItem.submenu
        previousItem.submenu = nil
        previousItem.submenu = submenu
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate
{
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        completionHandler([.alert, .sound, .badge])
    }
}
