//
//  UserDetailViewController.swift
//  Syllable
//
//  Created by Jarvis Zhaowei Wu on 2021-03-30.
//  Copyright © 2021 jarviswu. All rights reserved.
//

import UIKit
import SKCountryPicker
import AVFoundation
import FirebaseStorage
import FirebaseDatabase

class UserDetailViewController: UIViewController, AVAudioRecorderDelegate {

    var user: User!

    let lightHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    let mediumHapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    var audioPlayer: AVAudioPlayer!
    var audioRecorder: AVAudioRecorder!
    var audioSession: AVAudioSession!

    var storageRef = Storage.storage().reference()
    var databaseRef = Database.database().reference()

    var practiceMode = RecordPlayMode.record {
        didSet {
            if practiceMode == .play {
                requestEvaluationButton.enable()
                discardButton.isEnabled = true
            } else {
                requestEvaluationButton.disable()
                discardButton.isEnabled = false
            }
        }
    }

    /// - TODO: put everything in a scroll view

    @IBOutlet weak var profileCardBackgroundView: UIView!
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var fullNameLabel: UILabel!
    @IBOutlet weak var secondaryInfoLabel: UILabel!
    @IBOutlet weak var bioLabel: UILabel!
    @IBOutlet weak var flagImageView: UIImageView!

    @IBOutlet weak var playerCardBackgroundView: UIView!
    @IBOutlet weak var playerButton: UIButton!
    @IBOutlet weak var waveformView: FDWaveformView!
    @IBOutlet weak var waveformLoadingActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var waveformLoadingLabel: UILabel!

    @IBOutlet weak var practiceCardBackgroundView: UIView!
    @IBOutlet weak var practiceTitleLabel: UILabel!
    @IBOutlet weak var threeButtonsStackView: UIStackView!
    @IBOutlet weak var recordButtonBackgroundView: UIView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var learnedButton: UIButton!
    @IBOutlet weak var needPracticeButton: UIButton!
    @IBOutlet weak var discardButton: UIButton!
    @IBOutlet weak var requestEvaluationButton: SButton!
    @IBOutlet weak var learnedCheckmarkView: UIView!
    @IBOutlet weak var needPracticeCheckmarkView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setPracticeMode(mode: practiceMode)
        addGestures()
        preparePlaying()
        lightHapticGenerator.prepare()
        loadAudio()
    }

    func setupUI() {
        profileCardBackgroundView.layer.cornerRadius = 12
        profileCardBackgroundView.layer.masksToBounds = true
        profileImageView.layer.cornerRadius = profileImageView.frame.height / 2
        profileImageView.image = user?.profilePicture
        fullNameLabel.text = user?.getFullName()
        secondaryInfoLabel.text = user?.getSecondaryLabel()
        bioLabel.text = user.getBio()
        if let countryCode = user.country?.countryCode {
            flagImageView.layer.cornerRadius = 4
            flagImageView.clipsToBounds = true
            flagImageView.contentMode = .scaleAspectFill
            flagImageView.image = Country(countryCode: countryCode).flag
        } else {
            flagImageView.removeFromSuperview()
        }

        playerCardBackgroundView.layer.cornerRadius = 12
        waveformView.wavesColor = UIColor.systemGray4
        waveformView.progressColor = UIColor.systemBlue
        playerButton.isEnabled = false
        waveformLoadingActivityIndicator.startAnimating()

        practiceCardBackgroundView.layer.cornerRadius = 12
        recordButtonBackgroundView.layer.cornerRadius = recordButtonBackgroundView.frame.height / 2
        recordButton.layer.cornerRadius = recordButton.frame.height / 2
        learnedButton.layer.cornerRadius = learnedButton.frame.height / 2
        needPracticeButton.layer.cornerRadius = needPracticeButton.frame.height / 2
        requestEvaluationButton.disable()
        discardButton.isEnabled = false
        recordButton.adjustsImageWhenHighlighted = false
        learnedButton.adjustsImageWhenHighlighted = false
        needPracticeButton.adjustsImageWhenHighlighted = false

        configureStatus()

        if user.id == User.currentUser!.id {
            practiceTitleLabel.text = "To edit your own profile and name pronunciation, go to Settings."
            threeButtonsStackView.isHidden = true
            discardButton.isHidden = true
            requestEvaluationButton.isHidden = true
            recordButtonBackgroundView.isHidden = true
        }
    }

    func addGestures() {
        let holdGesture = UILongPressGestureRecognizer(target: self, action: #selector(didTapHoldRecordButton))
        holdGesture.minimumPressDuration = 0.3
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapRecordButton))
        recordButton.addGestureRecognizer(holdGesture)
        recordButton.addGestureRecognizer(tapGesture)
    }

    func configureStatus() {
        // show current learning status, if any
        if user.status != .learned {
            learnedCheckmarkView.isHidden = true
        }
        if user.status != .needPractice {
            needPracticeCheckmarkView.isHidden = true
        }
        learnedCheckmarkView.layer.cornerRadius = learnedCheckmarkView.frame.height / 2
        learnedCheckmarkView.layer.borderColor = UIColor.systemGreen.cgColor
        learnedCheckmarkView.layer.borderWidth = 1.5
        needPracticeCheckmarkView.layer.cornerRadius = needPracticeCheckmarkView.frame.height / 2
        needPracticeCheckmarkView.layer.borderColor = UIColor.systemYellow.cgColor
        needPracticeCheckmarkView.layer.borderWidth = 1.5
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    func loadAudio() {
        print("retrieve recording and play for user \(user.id).")
        lightHapticGenerator.impactOccurred()
        lightHapticGenerator.prepare()

        let localUrl = getDocumentsDirectory().appendingPathComponent("\(user.id).m4a")
        let audioRef = self.storageRef.child("audio-recordings/\(user.id).m4a")

        let _ = audioRef.write(toFile: localUrl) { (url, error) in
            if let error = error {
                print("Error when downloading the audio: \(error.localizedDescription)")
            } else {
                self.waveformLoadingActivityIndicator.stopAnimating()
                self.waveformLoadingLabel.isHidden = true
                self.playerButton.isEnabled = true
                self.waveformView.audioURL = localUrl
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

    @IBAction func didTapPlayButton(_ sender: UIButton) {
        let audioURL = getDocumentsDirectory().appendingPathComponent("\(user.id).m4a")
        let asset = AVURLAsset(url: audioURL, options: nil)
        let audioDuration = asset.duration
        let audioDurationSeconds = CMTimeGetSeconds(audioDuration)
        lightHapticGenerator.impactOccurred()
        lightHapticGenerator.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                self.audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                self.audioPlayer.play()
            } catch {
                print("Play failed")
            }
        }
        self.waveformView.highlightedSamples = Range<Int>(0...0)
        UIView.animate(withDuration: audioDurationSeconds) {
            self.waveformView.highlightedSamples = Range<Int>(0...self.waveformView.totalSamples)
        }
    }

    @IBAction func didTapLearnedButton(_ sender: UIButton) {
        lightHapticGenerator.impactOccurred()
        lightHapticGenerator.prepare()
        if user.status == .learned {
            print("already learned")
            // should we provide a way to deselect a status here??
        } else {
            databaseRef.child("statuses/\(User.currentUser!.id)/\(user.id)").setValue("learned") { (error, reference) in
                if let error = error {
                    print("Error when updating status: \(error.localizedDescription)")
                } else {
                    self.learnedCheckmarkView.isHidden = false
                    self.needPracticeCheckmarkView.isHidden = true
                    self.user.setStatus(status: .learned)
                }
            }
        }
    }

    @IBAction func didTapNeedPracticeButton(_ sender: UIButton) {
        lightHapticGenerator.impactOccurred()
        lightHapticGenerator.prepare()
        if user.status == .needPractice {
            print("already needPractice")
            // should we provide a way to deselect a status here??
        } else {
            databaseRef.child("statuses/\(User.currentUser!.id)/\(user.id)").setValue("needPractice") { (error, reference) in
                if let error = error {
                    print("Error when updating status: \(error.localizedDescription)")
                } else {
                    self.learnedCheckmarkView.isHidden = true
                    self.needPracticeCheckmarkView.isHidden = false
                    self.user.setStatus(status: .needPractice)
                }
            }
        }
    }

    @IBAction func didTapDiscardButton(_ sender: UIButton) {
        let currentUser = User.currentUser!
        let fileName = "practice-\(currentUser.id)-\(user.id).m4a"
        let audioFilename = getDocumentsDirectory().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: audioFilename)
        setPracticeMode(mode: .record)
    }

    @IBAction func didTapRequestEvaluationButton(_ sender: UIButton) {
        requestEvaluationButton.disable()
        let currentUser = User.currentUser!
        let fileName = "practice-\(currentUser.id)-\(user.id).m4a"
        let audioURL = getDocumentsDirectory().appendingPathComponent(fileName)
        let storageRef = Storage.storage().reference().child("practice-audio-recordings/\(fileName)")
        let metadata = StorageMetadata()
        metadata.contentType = "audio/m4a"
        storageRef.putFile(from: audioURL, metadata: metadata) { (metadata, error) in
            if let error = error {
                print("Error when uploading practice recording: \(error.localizedDescription)")
            } else {
                self.setPracticeMode(mode: .record)
                let timestamp = Date().timeIntervalSince1970
                self.databaseRef.child("practices").child(self.user.id).child(User.currentUser!.id).setValue(timestamp) { (error, ref) in
                    if let error = error {
                        print("Error when uploading practice timestamp: \(error.localizedDescription)")
                    } else {
                        // push notificatios to the other user?
                        // show toast message?
                    }
                }
            }
        }
    }

    func setPracticeMode(mode: RecordPlayMode) {
        let animationDuration = self.practiceMode == mode ? 0 : 0.3
        self.practiceMode = mode
        switch mode {
        case .record:
            UIView.animate(withDuration: animationDuration) {
                self.recordButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
                // self.startOverButton.isHidden = true
            }
        case .play:
            UIView.animate(withDuration: animationDuration) {
                self.recordButton.setImage(UIImage(systemName: "headphones"), for: .normal)
                // self.startOverButton.isHidden = false
            }
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            finishRecording(success: false)
        }
    }

    func startRecording() {
        let currentUser = User.currentUser!
        let fileName = "practice-\(currentUser.id)-\(user.id).m4a"
        let audioFilename = getDocumentsDirectory().appendingPathComponent(fileName)

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        mediumHapticGenerator.prepare()
        mediumHapticGenerator.impactOccurred()

        // need to have this delay, otherwise the haptic is not fired (yes super weird I know)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                self.audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
                self.audioRecorder.delegate = self
                self.audioRecorder.record()
            } catch {
                self.finishRecording(success: false)
            }
        }
    }

    func finishRecording(success: Bool) {
        audioRecorder.stop()
        audioRecorder = nil

        lightHapticGenerator.prepare()
        lightHapticGenerator.impactOccurred()

        if success {
            setPracticeMode(mode: .play)
        } else {
            setPracticeMode(mode: .record) // or error mode?
        }
    }

    @objc func didTapHoldRecordButton(sender : UIGestureRecognizer) {
        guard practiceMode == .record else { return }
        if sender.state == .began {
            guard audioRecorder == nil else { return }
            startRecording()
            // Begin animation
            UIView.animate(withDuration: 0.8, delay: 0, options: [.repeat, .curveEaseInOut], animations: {
                self.recordButtonBackgroundView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                self.recordButtonBackgroundView.backgroundColor = .clear
            })
        } else if sender.state == .ended {
            // End animation
            self.recordButtonBackgroundView.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseIn], animations: {
                self.recordButtonBackgroundView.backgroundColor = .clear
            }) { (_) in
                self.recordButtonBackgroundView.layer.removeAllAnimations()
                self.recordButtonBackgroundView.transform = .identity
                self.recordButtonBackgroundView.backgroundColor = .systemBlue
            }
            finishRecording(success: true)
        }
    }

    @objc func didTapRecordButton(sender : UIGestureRecognizer) {
        guard practiceMode == .play else { return }
        let currentUser = User.currentUser!
        let fileName = "practice-\(currentUser.id)-\(user.id).m4a"
        let audioURL = getDocumentsDirectory().appendingPathComponent(fileName)

        do {
            lightHapticGenerator.prepare()
            lightHapticGenerator.impactOccurred()
            UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseInOut], animations: {
                self.recordButtonBackgroundView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                self.recordButtonBackgroundView.backgroundColor = .clear
            }) { (_) in
                self.recordButtonBackgroundView.transform = .identity
                self.recordButtonBackgroundView.backgroundColor = .systemBlue
            }
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer.play()
            // add animation
        } catch {
            print("play failed")
        }
    }

}
