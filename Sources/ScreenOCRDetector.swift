import AppKit
import CoreGraphics
import Foundation
import Vision

/// Fallback detector: OCR the Chrome window for Claude permission copy.
enum ScreenOCRDetector {
    static func scanChromeForPermissionDialog() -> (present: Bool, site: String, text: String) {
        guard let pid = ChromeFinder.runningChromeApps().first?.processIdentifier else {
            return (false, "", "")
        }

        guard let image = captureWindow(ownedBy: pid) else {
            return (false, "", "")
        }

        let text = recognizeText(in: image)
        let lower = text.lowercased()

        let present =
            (lower.contains("new permissions required") && lower.contains("allow this action"))
            || (lower.contains("claude wants to") && lower.contains("allow this action"))
            || (lower.contains("always allow actions on this site") && lower.contains("claude"))

        guard present else { return (false, "", text) }

        let site = extractSite(from: text) ?? ""
        return (true, site, text)
    }

    private static func captureWindow(ownedBy pid: pid_t) -> CGImage? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Prefer the largest on-screen Chrome window (main browser, not tiny panels).
        var bestID: CGWindowID?
        var bestArea: CGFloat = 0
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let area = bounds.width * bounds.height
            if area > bestArea {
                bestArea = area
                bestID = windowID
            }
        }

        guard let windowID = bestID else { return nil }
        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    private static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func extractSite(from text: String) -> String? {
        let pattern = #"on:\s*((?:www\.)?[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return DomainMatcher.normalize(String(text[r]))
    }
}
