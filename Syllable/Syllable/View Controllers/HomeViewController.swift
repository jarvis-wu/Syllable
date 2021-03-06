//
//  HomeViewController.swift
//  Syllable
//
//  Created by Jarvis Zhaowei Wu on 2021-02-25.
//  Copyright © 2021 jarviswu. All rights reserved.
//

import UIKit
import AVFoundation
import FirebaseDatabase
import FirebaseStorage
import FirebaseAuth

enum Status {
    case none
    case learned
    case needPractice
}

class HomeViewController: UIViewController {

    var totalUsers = 0 // this might not work later if we have pagination
    var users = [User]() {
        didSet {
            if totalUsers != 0 && users.count == totalUsers { // in this way we only load the table once
                users.sort { $0.lastName! < $1.lastName! }
                tableView.reloadData()
            }
        }
    }
    var filteredUsers = [User]()

    var playingCell: HomeTableViewCell?

    var databaseRef = Database.database().reference()
    var storageRef = Storage.storage().reference()
    var refHandle: DatabaseHandle!

    var audioPlayer: AVAudioPlayer!
    var audioSession: AVAudioSession!

    var filterButtonActive = false

    var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }

    var isFiltering: Bool {
        return (searchController.isActive && !isSearchBarEmpty) || filterButtonActive
    }

    let searchController = UISearchController(searchResultsController: nil)
    let lightHapticGenerator = UIImpactFeedbackGenerator(style: .light)

    @IBOutlet weak var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.shadowImage = UIImage()
        populateUsers()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.tableHeaderView = UIView()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search for a name or a program"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        preparePlaying()
        if let filterButton = navigationItem.rightBarButtonItem {
            if #available(iOS 14.0, *) {
                filterButton.menu = createMenu()
            } else {
                // Fallback on earlier versions
                // e.g. action sheet
            }
        }
    }

    func preparePlaying() {
        audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true)
            audioSession.requestRecordPermission() { allowed in
                DispatchQueue.main.async { if !allowed { print("Permission denied") } }
            }
        } catch {
            print("Error when preparing audio recorder: \(error)")
        }
    }

    /// - TODO: pagination?
    private func populateUsers() {
        guard let currentUid = Auth.auth().currentUser?.uid else { return }
        refHandle = databaseRef.child("users").observe(DataEventType.value, with: { (snapshot) in
            self.users = []
            let dataDict = snapshot.value as? [String : [String : AnyObject]] ?? [:]
            self.totalUsers = dataDict.count
            for (userId, userInfoDict) in dataDict {
                var status = Status.none
                self.refHandle = self.databaseRef.child("statuses/\(currentUid)/\(userId)").observe(DataEventType.value, with: { (snapshot) in
                    let statusString = snapshot.value as? String
                    switch statusString {
                    case "learned":
                        status = .learned
                    case "needPractice":
                        status = .needPractice
                    default:
                        break // default none
                    }
                    var profileImage: UIImage? = nil
                    let profilePictureRef = self.storageRef.child("profile-pictures/\(userId).jpg")
                    profilePictureRef.getData(maxSize: 3 * 1024 * 1024) { (data, error) in
                        if let error = error {
                            print("Error when downloading the profile picture: \(error.localizedDescription)")
                        } else {
                            profileImage = UIImage(data: data!)
                        }
                        let user = User(id: userId, userInfoDict: userInfoDict, profilePicture: profileImage, status: status)
                        if user.id == Auth.auth().currentUser?.uid {
                            User.currentUser = user
                        }
                        if self.users.count != 0 && self.users.count == self.totalUsers {
                            // updating
                            if let index = self.users.firstIndex(where: {$0.id == user.id}) {
                                self.users[index] = user
                            }
                        } else {
                            // populating
                            self.users.append(user)
                        }
                    }
                })
            }
        })
    }

    func filterContentForSearchText(_ searchText: String) {
        filteredUsers = users.filter { (user: User) -> Bool in
            let fullNameMatch = (user.getFullName() ?? "").lowercased().contains(searchText.lowercased())
            let facultyMatch = (user.program ?? "").lowercased().contains(searchText.lowercased())
            let yearMatch = (user.classYear ?? "").lowercased().contains(searchText.lowercased())
            return fullNameMatch || facultyMatch || yearMatch
        }
        tableView.reloadData()
    }

    func createMenu() -> UIMenu {
        let needPractice = UIAction(
            title: "Difficult"
        ) { (_) in
            self.filterButtonActive = true
            self.title = "Filtering \"difficult\""
            self.filteredUsers = self.users.filter({ (user: User) -> Bool in
                return user.status == .needPractice
            })
            self.tableView.reloadData()
        }

        let noStatus = UIAction(
            title: "Other"
        ) { (_) in
            self.filterButtonActive = true
            self.title = "Filtering \"other\""
            self.filteredUsers = self.users.filter({ (user: User) -> Bool in
                return user.status == .none
            })
            self.tableView.reloadData()
        }

        let learned = UIAction(
            title: "Learned"
        ) { (_) in
            self.filterButtonActive = true
            self.title = "Filtering \"learned\""
            self.filteredUsers = self.users.filter({ (user: User) -> Bool in
                return user.status == .learned
            })
            self.tableView.reloadData()
        }

        let allItems = UIAction(
            title: "All"
        ) { (_) in
            self.filterButtonActive = false
            self.title = "Home"
            self.filteredUsers = self.users
            self.tableView.reloadData()
        }

        let menuActions = [needPractice, learned, noStatus, allItems]

        let filterMenu = UIMenu(
            title: "",
            children: menuActions)

        return filterMenu
    }

}

extension HomeViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isFiltering {
            return filteredUsers.count
        }
        return users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "HomeTableViewCell", for: indexPath) as? HomeTableViewCell else { return UITableViewCell() }
        let user: User
        if isFiltering {
            user = filteredUsers[indexPath.row]
        } else {
            user = users[indexPath.row]
        }
        cell.delegate = self
        cell.userId = user.id
        cell.nameLabel.text = user.getFullName()
        cell.secondaryInfoLabel.text = user.getSecondaryLabel()
        cell.profileImageView.image = user.profilePicture
        switch user.status {
        case .none:
            cell.statusView.backgroundColor = .systemGray5
        case .learned:
            cell.statusView.backgroundColor = .systemGreen
        case .needPractice:
            cell.statusView.backgroundColor = .systemYellow
        }
        let backgroundView = UIView()
        backgroundView.backgroundColor = .systemGray6
        cell.selectedBackgroundView = backgroundView
        return cell
    }

}

extension HomeViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let userDetailViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(identifier: "UserDetailViewController") as! UserDetailViewController
        userDetailViewController.user = isFiltering ? filteredUsers[indexPath.row] : users[indexPath.row]
        userDetailViewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(userDetailViewController, animated: true)
    }

}

extension HomeViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        let searchBar = searchController.searchBar
        filterContentForSearchText(searchBar.text!)
    }

}

extension HomeViewController: HomeTableViewCellDelegate {

    func shouldPlayPronunciation(withId id: String, from indexPath: IndexPath) {
        lightHapticGenerator.prepare()
        lightHapticGenerator.impactOccurred()
        let cell = tableView.cellForRow(at: indexPath) as! HomeTableViewCell
        cell.playButton.isHidden = true
        cell.audioLoadingActivityIndicator.startAnimating()
        let audioRef = self.storageRef.child("audio-recordings/\(id).m4a")
        audioRef.getData(maxSize: 1 * 1024 * 1024) { (data, error) in
            if let error = error {
                print("Error when downloading the audio recording: \(error.localizedDescription)")
            } else {
                cell.audioLoadingActivityIndicator.stopAnimating()
                cell.playButton.isHidden = false
                cell.playButton.tintColor = .systemBlue
                self.playingCell = cell
                do {
                    self.audioPlayer = try AVAudioPlayer(data: data!)
                    self.audioPlayer.delegate = self
                    self.audioPlayer.play()
                    // add animation
                } catch {
                    print("play failed")
                }
            }
        }
    }

}

extension HomeViewController: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if let cell = playingCell {
            cell.playButton.tintColor = .lightGray
        }
    }

}
