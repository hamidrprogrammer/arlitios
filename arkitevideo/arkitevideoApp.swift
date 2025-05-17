import UIKit
import ARKit
import SceneKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ARTestViewController()
        window?.makeKeyAndVisible()
        return true
    }
}

class ARTestViewController: UIViewController, ARSCNViewDelegate {
    private let arView = ARSCNView()
    private let startButton = UIButton(type: .system)
    private let debugLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .darkGray

        // Setup button
        startButton.setTitle("شروع تست", for: .normal)
        startButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = .systemBlue
        startButton.layer.cornerRadius = 10
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startButton)

        // Setup debug label
        debugLabel.text = "آماده برای تست"
        debugLabel.textColor = .white
        debugLabel.font = .systemFont(ofSize: 14)
        debugLabel.numberOfLines = 0
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugLabel)

        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 200),
            startButton.heightAnchor.constraint(equalToConstant: 50),

            debugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            debugLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            debugLabel.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 20)
        ])
    }

    @objc private func startTapped() {
        showMessage("✅ دکمه زده شد، بررسی پرمیشن دوربین...")

        checkCameraPermission { granted in
            guard granted else {
                self.showMessage("❌ دسترسی دوربین رد شد")
                return
            }

            DispatchQueue.main.async {
                self.showMessage("✅ دسترسی دوربین داده شد. اجرای ARKit...")
                self.setupARView()
                self.runAR()
            }
        }
    }

    private func setupARView() {
        arView.delegate = self
        arView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(arView, belowSubview: startButton)

        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func runAR() {
        let config = ARWorldTrackingConfiguration()
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        showMessage("✅ ARKit راه‌اندازی شد")
    }

    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    private func showMessage(_ msg: String) {
        DispatchQueue.main.async {
            self.debugLabel.text = msg
        }
    }
}
