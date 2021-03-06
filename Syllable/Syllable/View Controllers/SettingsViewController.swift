//
//  SettingsViewController.swift
//  Syllable
//
//  Created by Jarvis Zhaowei Wu on 2021-03-28.
//  Copyright © 2021 jarviswu. All rights reserved.
//

import UIKit
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
import MessageUI

enum SettingsSection: Int, CaseIterable {
    case settings = 0
    case support
    case logout
}

struct SettingsRowData {
    let rowTitle: String
    let rowIconName: String
}

let settingsData: [[SettingsRowData]] = [
    [
        SettingsRowData(rowTitle: "Dark mode", rowIconName: "night"),
        SettingsRowData(rowTitle: "Data and storage", rowIconName: "database"),
        SettingsRowData(rowTitle: "Language", rowIconName: "global"),
        SettingsRowData(rowTitle: "Invite friends", rowIconName: "customer")
    ], [
        SettingsRowData(rowTitle: "Contact us", rowIconName: "email"),
        SettingsRowData(rowTitle: "Syllable FAQ", rowIconName: "question")
    ], [
        SettingsRowData(rowTitle: "Log out", rowIconName: "door")
    ]
]

class SettingsViewController: UIViewController {

    var databaseRef = Database.database().reference()
    var storageRef = Storage.storage().reference()
    var refHandle: DatabaseHandle!

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var profilePictureImageView: UIImageView!
    @IBOutlet weak var fullNameLabel: UILabel!
    @IBOutlet weak var secondaryLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.sectionFooterHeight = 10
        tableView.alwaysBounceVertical = false
    }

    override func viewWillAppear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        super.viewWillAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        super.viewWillDisappear(animated)
    }

    func setupHeader() {
        profilePictureImageView.layer.cornerRadius = profilePictureImageView.frame.height / 2
        if let user = User.currentUser {
            profilePictureImageView.image = user.profilePicture
            fullNameLabel.text = user.getFullName()
            secondaryLabel.text = user.getSecondaryLabel()
        } else {
            guard let currentUid = Auth.auth().currentUser?.uid else { return }
            refHandle = databaseRef.child("users/\(currentUid)").observe(DataEventType.value, with: { (snapshot) in
                let dataDict = snapshot.value as? [String : AnyObject] ?? [:]
                var profileImage: UIImage? = nil
                let profilePictureRef = self.storageRef.child("profile-pictures/\(currentUid).jpg")
                profilePictureRef.getData(maxSize: 3 * 1024 * 1024) { (data, error) in
                    if let error = error {
                        print("Error when downloading the profile picture: \(error.localizedDescription)")
                    } else {
                        profileImage = UIImage(data: data!)
                    }
                    let user = User(id: currentUid, userInfoDict: dataDict, profilePicture: profileImage, status: .none)
                    User.currentUser = user // duplication? harmless redundance?
                    self.profilePictureImageView.image = user.profilePicture
                    self.fullNameLabel.text = user.getFullName()
                    self.secondaryLabel.text = user.getSecondaryLabel()
                }
            })
        }
    }

    @IBAction func didTapEditButton(_ sender: UIButton) {
        tabBarController?.featureNotAvailable()
    }

    func sendContactEmail() {
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setToRecipients(["jarviszwu@gmail.com"])
            mail.setMessageBody("<p>Contact Syllable's developer.</p>", isHTML: true)

            present(mail, animated: true)
        } else {
            // show failure alert
        }
    }

    func openFAQ() {
        if let url = URL(string: "https://www.notion.so/Syllable-FAQs-080dd01ef3b74e7cb888fc1622c4f622") {
            UIApplication.shared.open(url)
        }
    }

    func logout(){
        let alertController = UIAlertController(title: "Confirm Logout", message: nil, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Log out", style: .default, handler: { (action) in
            do {
                try Auth.auth().signOut()
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let rootNavigationViewController = storyboard.instantiateViewController(identifier: "RootNavigationViewController") as! UINavigationController
                let landingViewController = storyboard.instantiateViewController(identifier: "LandingViewController")
                rootNavigationViewController.viewControllers = [landingViewController]
                rootNavigationViewController.modalPresentationStyle = .fullScreen
                self.present(rootNavigationViewController, animated: true, completion: nil) // is this the right way?
            } catch let error {
                print(error.localizedDescription)
            }
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

}

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return SettingsSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settingsData[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTableViewCell", for: indexPath) as? SettingsTableViewCell else { return UITableViewCell() }
        cell.labelView.text = settingsData[indexPath.section][indexPath.row].rowTitle
        cell.iconImageView.image = UIImage(named: settingsData[indexPath.section][indexPath.row].rowIconName)
        let backgroundView = UIView()
        backgroundView.backgroundColor = .systemGray6
        cell.selectedBackgroundView = backgroundView
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = SettingsSection(rawValue: section)!
        switch section {
        case .settings:
            return "Settings"
        case .support:
            return "Support"
        case .logout:
            return "Account"
        }
    }

}

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                tabBarController?.featureNotAvailable()
            case 1:
                tabBarController?.featureNotAvailable()
            case 2:
                tabBarController?.featureNotAvailable()
            case 3:
                tabBarController?.featureNotAvailable()
            default:
                break
            }
        case 1:
            switch indexPath.row {
            case 0:
                sendContactEmail()
            case 1:
                openFAQ()
            default:
                break
            }
        case 2:
            switch indexPath.row {
            case 0:
                logout()
            default:
                break
            }
        default:
            break
        }
    }

}

extension SettingsViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }

}
