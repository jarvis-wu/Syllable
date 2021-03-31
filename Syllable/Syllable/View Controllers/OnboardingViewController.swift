//
//  OnboardingViewController.swift
//  Syllable
//
//  Created by Jarvis Zhaowei Wu on 2021-02-25.
//  Copyright © 2021 jarviswu. All rights reserved.
//

import UIKit
import SKCountryPicker
import GoogleSignIn
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage

class OnboardingViewController: UIViewController {

    @IBOutlet weak var avatarButton: UIButton!
    @IBOutlet weak var firstNameField: UITextField!
    @IBOutlet weak var middleNameField: UITextField!
    @IBOutlet weak var lastNameField: UITextField!
    @IBOutlet weak var countryButton: UIButton!
    @IBOutlet weak var continueButton: SButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    var newUser: User!
    var databaseRef = Database.database().reference()
    var storageRef = Storage.storage().reference()

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let _: GIDGoogleUser = GIDSignIn.sharedInstance()?.currentUser,
              let user = Auth.auth().currentUser else { return }

        continueButton.disable()
        avatarButton.adjustsImageWhenHighlighted = false
        setupEmptyAvatar()

        firstNameField.delegate = self
        firstNameField.tag = 0
        middleNameField.delegate = self
        middleNameField.tag = 1
        lastNameField.delegate = self
        lastNameField.tag = 2

        for (index, field) in [lastNameField, middleNameField, firstNameField].enumerated() {
            field?.keyboardDistanceFromTextField = 50 + CGFloat(index * 60)
        }

        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil) // remove back button title

        newUser = User(id: user.uid)
        newUser.delegate = self

        hapticGenerator.prepare()
    }

    @IBAction func didTapAvatarButton(_ sender: UIButton) {
        // present options: select from cameral roll; take a new picture; remove current (if already selected)
        hapticGenerator.impactOccurred()
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { _ in
            self.openCamera()
        }))

        alert.addAction(UIAlertAction(title: "Choose from library", style: .default, handler: { _ in
            self.openGallery()
        }))

        if newUser.profilePicture != nil {
            alert.addAction(UIAlertAction(title: "Remove current photo", style: .destructive, handler: { _ in
                self.removeProfilePicture()
            }))
        }

        alert.addAction(UIAlertAction.init(title: "Cancel", style: .cancel, handler: nil))

        self.present(alert, animated: true, completion: nil)
    }

    @IBAction func didTapLanguageOriginButton(_ sender: UIButton) {
        if newUser.country != nil {
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

            alert.addAction(UIAlertAction(title: "Select new country", style: .default, handler: { _ in
                self.openCountryPickerController()
            }))

            alert.addAction(UIAlertAction(title: "Remove current selection", style: .destructive, handler: { _ in
                self.newUser.setCountry(country: nil)
                self.countryButton.setTitle("Name origin", for: .normal)
                self.countryButton.setTitleColor(.placeholderText, for: .normal)
            }))

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        } else {
            openCountryPickerController()
        }
    }

    @IBAction func didTapContinueButton(_ sender: SButton) {
        continueButton.disable()
        activityIndicator.startAnimating()
        completeProfile()
    }

    /// - TODO: use "defer" to prevent duplication
    func completeProfile() {
        // Upload basic info to realtime database
        databaseRef.child("users").child(newUser.id).setValue([
            "firstName" : newUser.firstName,
            "middleName" : newUser.middleName,
            "lastName" : newUser.lastName,
            "countryCode" : newUser.country?.countryCode,
            "countryName" : newUser.country?.name
        ]) { (error, ref) in
            if let error = error {
                print("Error when uploading basic info: \(error.localizedDescription)")
                self.activityIndicator.stopAnimating()
            } else {
                // Uploading profile pic
                var hasError = false
                defer {
                    self.activityIndicator.stopAnimating()
                    if !hasError {
                        self.performSegue(withIdentifier: "ShowInitialRecordViewController", sender: self)
                    }
                }
                guard let originalPicture = self.newUser.profilePicture else { return }
                ImageResizer.resize(image: originalPicture, maxByte: 300000) { image in
                    guard let resizedImage = image else { return }
                    if let profilePictureData: Data = resizedImage.jpegData(compressionQuality: 1.0) {
                        let metadata = StorageMetadata()
                        metadata.contentType = "image/jpg"
                        let pictureStorageRef = self.storageRef.child("profile-pictures/\(self.newUser.id).jpg")
                        pictureStorageRef.putData(profilePictureData, metadata: metadata) { (metadata, error) in
                            if let error = error {
                                hasError = true
                                print("Error when uploading profile picture: \(error.localizedDescription)")
                            }
                            return
                        }
                    }
                }
            }
        }
    }

    func openCountryPickerController() {
        let countryPickerCountry = CountryPickerWithSectionViewController.presentController(on: self) { (country) in
            let selectedCountry = SCountry(name: country.countryName, countryCode: country.countryCode)
            self.newUser.setCountry(country: selectedCountry)
            self.countryButton.setTitle(selectedCountry.name, for: .normal)
            self.countryButton.setTitleColor(.black, for: .normal)
        }
        countryPickerCountry.title = "Select a country"
        countryPickerCountry.labelFont = UIFont.systemFont(ofSize: 15)
        countryPickerCountry.separatorLineColor = .clear
//        countryPickerCountry.favoriteCountriesLocaleIdentifiers = ["TW", "CA"]
        countryPickerCountry.flagStyle = .corner
        countryPickerCountry.isCountryDialHidden = true
    }

    func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.camera) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = UIImagePickerController.SourceType.camera
            imagePicker.allowsEditing = true
            self.present(imagePicker, animated: true, completion: nil)
        } else {
            let alert  = UIAlertController(title: "Warning", message: "You don't have camera", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }

    func openGallery() {
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.photoLibrary){
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.allowsEditing = true
            imagePicker.sourceType = UIImagePickerController.SourceType.photoLibrary
            self.present(imagePicker, animated: true, completion: nil)
        } else {
            let alert  = UIAlertController(title: "Warning", message: "You don't have permission to access gallery.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }

    func removeProfilePicture() {
        newUser.setProfilePicture(profilePicture: nil)
        avatarButton.setImage(UIImage(systemName: "camera.fill") , for: .normal)
    }

    func setupAvatar(with image: UIImage) {
        newUser.setProfilePicture(profilePicture: image)
        avatarButton.setImage(image, for: .normal)
    }

    func setupEmptyAvatar() {
        avatarButton.layer.cornerRadius = avatarButton.frame.height / 2
        let gradient = CAGradientLayer()
        gradient.frame = avatarButton.bounds
        gradient.cornerRadius = gradient.frame.height / 2
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.colors = [UIColor(red: 155/255, green: 218/255, blue: 125/255, alpha: 1).cgColor,
                           UIColor(red: 89/255, green: 201/255, blue: 108/255, alpha: 1).cgColor].compactMap { $0 }
        avatarButton.layer.insertSublayer(gradient, below: avatarButton.imageView?.layer)
        avatarButton.setImage(UIImage(systemName: "camera.fill") , for: .normal)
        avatarButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold), forImageIn: .normal)
        avatarButton.tintColor = .white
        avatarButton.clipsToBounds = true
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowInitialRecordViewController", let destination = segue.destination as? InitialRecordViewController {
            // pass the user object
            destination.newUser = self.newUser
        }
    }

}

extension OnboardingViewController: UINavigationControllerDelegate, UIImagePickerControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var newImage: UIImage

        if let possibleImage = info[.editedImage] as? UIImage {
            newImage = possibleImage
        } else if let possibleImage = info[.originalImage] as? UIImage {
            newImage = possibleImage
        } else {
            return
        }

        setupAvatar(with: newImage)
        picker.dismiss(animated: true)
    }

}

extension OnboardingViewController: UserEditDelegate {

    func didUpdateUserInformation() {
        if newUser.filledAllRequiredFields() {
            continueButton.enable()
        } else {
            continueButton.disable()
        }
    }

}

extension OnboardingViewController: UITextFieldDelegate {

    func textFieldDidEndEditing(_ textField: UITextField) {
        /// - TODO: preprocess? e.g. trim leading and trailing whitespace?
        switch textField.tag {
        case 0:
            newUser.setFirstName(firstName: textField.text)
        case 1:
            newUser.setMiddleName(middleName: textField.text)
        case 2:
            newUser.setLastName(lastName: textField.text)
        default:
            return
        }
    }

}
