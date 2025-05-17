import UIKit
import ARKit
import SceneKit
import AVFoundation

// MARK: - Models

struct MediaResponse: Codable {
    let status: Int
    let data: MediaData
    let message: String
}

struct MediaData: Codable {
     let state: Int
    let dataContent: [MediaItemRaw]
}

struct MediaItemRaw: Codable {
   let clubId: Int
    let adminId: Int
    let name: String
    let video: String
    let object: String
    let mapLa: String
    let mapLo: String
    let card: String? // null allowed
    let image: String
    let isRemoved: Bool
    let isPassword: Bool
    let type: String
    let fullName: String
    let instagram: String
    let facebook: String
    let twitter: String
    let email: String
    let phone: String
    let avatar: String
    let description: String
    let latitude: String
    let longitude: String
    let addressSite: String
    let ytb: String
    let seen: Int
    let id: Int
    let insertTime: String
    let updateTime: String?
}

struct MediaItem {
    let imageUrl: URL
    let videoUrl: URL
}

// MARK: - App Entry Point

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ARViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

// MARK: - Main View Controller

class ARViewController: UIViewController, ARSCNViewDelegate {
    private let arView = ARSCNView()
    private let debugLabel = UILabel()
    private let collectionView: UICollectionView

    private var mediaItems = [MediaItem]()
    private var referenceImages = Set<ARReferenceImage>()
    private var videoURLsByName = [String: URL]()

    private var thumbnails: [UIImage] = []

    init() {
        // Layout for bottom thumbnail bar
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
        self.collectionView.dataSource = self
        self.collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "thumbCell")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkCameraPermission()
        setupUI()
        fetchMediaItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        runARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }

    // MARK: - Permissions

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    self.showError("Camera permission denied")
                }
            }
        default:
            showError("Camera access is needed. Please enable it in Settings.")
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        arView.delegate = self
        arView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arView)

        debugLabel.textColor = .white
        debugLabel.font = .systemFont(ofSize: 12)
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        debugLabel.numberOfLines = 0
        view.addSubview(debugLabel)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 100),

            debugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            debugLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            debugLabel.bottomAnchor.constraint(equalTo: collectionView.topAnchor, constant: -8)
        ])
    }

    // MARK: - Networking

    private func fetchMediaItems() {
        guard let url = URL(string: "https://club.mamakschool.ir/club.backend/ClubAdmin/GetAllImageARGuest") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let params = [
            "clubId": "0",
            "adminId": "1"
        ]

        for (key, value) in params {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.showError("Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                self.showError("No data received")
                return
            }

            do {
                let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
                let filtered = decoded.data.dataContent
                    .filter { $0.type == "video" }
                    .compactMap { raw -> MediaItem? in
                        guard let img = raw.image, let vid = raw.video,
                              let imgURL = URL(string: img), let vidURL = URL(string: vid) else {
                            return nil
                        }
                        return MediaItem(imageUrl: imgURL, videoUrl: vidURL)
                    }

                DispatchQueue.main.async {
                    self.mediaItems = filtered
                    self.downloadReferenceImages()
                }

            } catch {
                self.showError("JSON decode error: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func downloadReferenceImages() {
        for item in mediaItems {
            URLSession.shared.dataTask(with: item.imageUrl) { data, _, error in
                guard let data = data, error == nil,
                      let image = UIImage(data: data),
                      let cgImage = image.cgImage else {
                    self.showError("Image download failed: \(error?.localizedDescription ?? "unknown")")
                    return
                }

                let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: 0.2)
                refImage.name = item.imageUrl.absoluteString

                DispatchQueue.main.async {
                    self.referenceImages.insert(refImage)
                    self.videoURLsByName[item.imageUrl.absoluteString] = item.videoUrl
                    self.thumbnails.append(image)
                    self.collectionView.reloadData()
                    self.runARSession()
                }
            }.resume()
        }
    }

    // MARK: - AR Session

    private func runARSession() {
        guard !referenceImages.isEmpty else {
            showError("No reference images loaded")
            return
        }

        let config = ARImageTrackingConfiguration()
        config.trackingImages = referenceImages
        config.maximumNumberOfTrackedImages = referenceImages.count
        arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
        debugLabel.text = "AR session started. Loaded: \(referenceImages.count) images."
    }

    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor,
              let name = imageAnchor.referenceImage.name,
              let videoURL = videoURLsByName[name] else { return }

        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)

        let videoNode = SKVideoNode(avPlayer: player)
        videoNode.play()

        let videoSize = CGSize(width: 1024, height: 1024)
        let skScene = SKScene(size: videoSize)
        videoNode.position = CGPoint(x: videoSize.width / 2, y: videoSize.height / 2)
        videoNode.size = videoSize
        skScene.addChild(videoNode)

        let plane = SCNPlane(
            width: imageAnchor.referenceImage.physicalSize.width,
            height: imageAnchor.referenceImage.physicalSize.height
        )
        plane.firstMaterial?.diffuse.contents = skScene
        plane.firstMaterial?.isDoubleSided = true

        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2
        node.addChildNode(planeNode)
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            self.debugLabel.text = "⚠️ \(message)"
        }
    }
}

// MARK: - CollectionView

extension ARViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return thumbnails.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "thumbCell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let imageView = UIImageView(image: thumbnails[indexPath.item])
        imageView.frame = cell.contentView.bounds
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        cell.contentView.addSubview(imageView)
        return cell
    }
}
