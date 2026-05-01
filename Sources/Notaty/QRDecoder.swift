import AppKit
import Vision

struct DetectedQR {
    let payload: String
    let boundingBox: CGRect
}

enum QRDecoder {
    /// Detects QR codes in the given image and returns DetectedQR records
    /// in detection order. Empty payloads are skipped. On any failure,
    /// returns an empty array — barcode detection must never block downstream
    /// OCR. Completion is dispatched to the main queue.
    static func detect(image: CGImage, completion: @escaping ([DetectedQR]) -> Void) {
        let request = VNDetectBarcodesRequest { request, error in
            if let error {
                NSLog("Notaty QR: detection error — \(error.localizedDescription)")
                DispatchQueue.main.async { completion([]) }
                return
            }
            let observations = (request.results as? [VNBarcodeObservation]) ?? []
            let detected = observations.compactMap { obs -> DetectedQR? in
                guard let value = obs.payloadStringValue, !value.isEmpty else {
                    return nil
                }
                return DetectedQR(payload: value, boundingBox: obs.boundingBox)
            }
            DispatchQueue.main.async { completion(detected) }
        }
        request.symbologies = [.qr]

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                NSLog("Notaty QR: handler error — \(error.localizedDescription)")
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}
