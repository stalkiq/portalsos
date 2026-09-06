import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class CameraEngine: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false

    @Published var lastImage: UIImage?
    @Published var hasCamera = false
    @Published var isRunning = false
    @Published var statusText = "Point at a sign, receipt, whiteboard, or product, then tap shutter."

    var jpegData: Data? {
        Self.compressedJPEG(from: lastImage)
    }

    var insightContext: String? {
        guard lastImage != nil else { return nil }
        return "The user captured a photo in PortalOS Camera for Token Factory vision. Read any sign, receipt, whiteboard, handwriting, label, or product. Transcribe visible text first, then suggest useful next actions."
    }

    func prepare() {
        hasCamera = AVCaptureDevice.default(for: .video) != nil
        if !hasCamera {
            statusText = "Simulator has no camera. Pick a sign, receipt, whiteboard, or product from the library."
        }
    }

    func start() {
        prepare()
        guard hasCamera else { return }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                statusText = "Camera permission denied. Enable it in Settings."
                return
            }
            configureIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
            isRunning = session.isRunning
            statusText = "Point at a sign, receipt, whiteboard, or product, then tap shutter."
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
        isRunning = false
    }

    func capture() {
        guard hasCamera, session.isRunning else { return }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func setPickedImage(_ image: UIImage) {
        lastImage = image
        statusText = "Photo ready. Tap Read with Insight."
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            hasCamera = false
            statusText = "Camera is not available."
            return
        }
        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        isConfigured = true
    }

    static func compressedJPEG(from image: UIImage?, maxDimension: CGFloat = 1280, quality: CGFloat = 0.82) -> Data? {
        guard let image else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            return
        }
        Task { @MainActor in
            self.lastImage = image
            self.statusText = "Photo captured. Tap Read with Insight."
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

struct CameraAppView: View {
    @ObservedObject var engine: CameraEngine
    var onReadWithInsight: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))

            ZStack {
                if engine.hasCamera {
                    CameraPreviewView(session: engine.session)
                } else {
                    Color.black
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(engine.statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }

                VStack {
                    Spacer()
                    if let lastImage = engine.lastImage {
                        Image(uiImage: lastImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }
                }
            }

            VStack(spacing: 12) {
                Text(engine.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                HStack(spacing: 18) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }

                    Button(action: engine.capture) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 68, height: 68)
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 6))
                    }
                    .disabled(!engine.hasCamera)
                    .opacity(engine.hasCamera ? 1 : 0.35)

                    Color.clear.frame(width: 88, height: 40)
                }

                Button {
                    dismiss()
                    onReadWithInsight()
                } label: {
                    Text("Read with Insight")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            Color(red: 0.28, green: 0.42, blue: 0.95).opacity(engine.lastImage == nil ? 0.35 : 0.92),
                            in: Capsule()
                        )
                }
                .disabled(engine.lastImage == nil)
                .padding(.horizontal, 20)
            }
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    engine.setPickedImage(image)
                }
            }
        }
    }
}
