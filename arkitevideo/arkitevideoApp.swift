import UIKit
import ARKit
import SceneKit
import AVFoundation

// MARK: - Models

struct MediaResponse: Codable {
    let data: MediaData
}

struct MediaData: Codable {
    let result: [MediaItemRaw]
}

struct MediaItemRaw: Codable {
    let type: String
    let image: String?
    let video: String?
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
    private let thumbnailScroll = UIScrollView()
    private let arView = ARSCNView()
    
    private var mediaItems = [MediaItem]()
    private var referenceImages = Set<ARReferenceImage>()
    private var videoURLsByName = [String: URL]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupThumbnailScroll()
        setupARView()
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

    // MARK: - UI Setup

    private func setupThumbnailScroll() {
        thumbnailScroll.translatesAutoresizingMaskIntoConstraints = false
        thumbnailScroll.showsHorizontalScrollIndicator = false
        view.addSubview(thumbnailScroll)
        NSLayoutConstraint.activate([
            thumbnailScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            thumbnailScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailScroll.heightAnchor.constraint(equalToConstant: 80)
        ])
    }

    private func setupARView() {
        arView.delegate = self
        arView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: thumbnailScroll.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Networking & Data Handling
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
            guard let data = data, error == nil else {
                print("Network error:", error ?? "unknown")
                return
            }

            do {
                let decoded = try JSONDecoder().decode(MediaResponse.self, from: data)
                let filtered = decoded.data.result
                    .filter { $0.type == "video" }
                    .compactMap { item in
                        if let imgStr = item.image,
                           let vidStr = item.video,
                           let imgURL = URL(string: imgStr),
                           let vidURL = URL(string: vidStr) {
                            return MediaItem(imageUrl: imgURL, videoUrl: vidURL)
                        }
                        return nil
                    }

                DispatchQueue.main.async {
                    self.mediaItems = filtered
                    filtered.forEach { self.downloadReferenceImage(for: $0) }
                }
            } catch {
                print("JSON parse error:", error)
            }
        }.resume()
    }

    private func downloadReferenceImage(for item: MediaItem) {
        URLSession.shared.dataTask(with: item.imageUrl) { data, _, err in
            guard let data = data, err == nil,
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                print("Image download failed:", err ?? "unknown")
                return
            }

            let refImage = ARReferenceImage(cgImage, orientation: .up, physicalWidth: 0.2)
            let name = item.imageUrl.absoluteString
            refImage.name = name
            self.referenceImages.insert(refImage)
            self.videoURLsByName[name] = item.videoUrl

            DispatchQueue.main.async {
                self.addThumbnail(uiImage)
                self.runARSession()
            }
        }.resume()
    }

    // MARK: - Thumbnails

    private var thumbX: CGFloat = 8
    private func addThumbnail(_ image: UIImage) {
        let thumbSize: CGFloat = 64
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.frame = CGRect(x: thumbX, y: 8, width: thumbSize, height: thumbSize)
        thumbnailScroll.addSubview(imageView)
        thumbX += thumbSize + 8
        thumbnailScroll.contentSize = CGSize(width: thumbX, height: 80)
    }

    // MARK: - AR Session

    private func runARSession() {
        guard !referenceImages.isEmpty else { return }
        let config = ARImageTrackingConfiguration()
        config.trackingImages = referenceImages
        config.maximumNumberOfTrackedImages = referenceImages.count
        arView.session.run(config, options: [.removeExistingAnchors, .resetTracking])
    }

    // MARK: - ARSCNViewDelegate

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor,
              let name = imageAnchor.referenceImage.name,
              let videoURL = videoURLsByName[name] else {
            return
        }

        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)

        let videoNode = SKVideoNode(avPlayer: player)
        videoNode.play()

        let skScene = SKScene(size: CGSize(width: 1024, height: 1024))
        videoNode.position = CGPoint(x: skScene.size.width/2, y: skScene.size.height/2)
        videoNode.size = skScene.size
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
}
