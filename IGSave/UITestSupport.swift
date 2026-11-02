#if DEBUG
import UIKit

enum UITestSupport {
    static func configureIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        URLProtocol.registerClass(DemoMediaProtocol.self)
    }
}

private final class DemoMediaProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "www.instagram.com" || request.url?.host == "demo.igsave.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isImage = request.url?.host == "demo.igsave.test"
        let data: Data
        if isImage {
            data = artwork(request.url?.lastPathComponent == "2")
        } else {
            let count = ProcessInfo.processInfo.arguments.contains("--long-album") ? 30 : 3
            let nodes = (1...count).map { index in
                ["node": ["is_video": false, "display_url": "https://demo.igsave.test/\(index)"]] as [String: Any]
            }
            let node: [String: Any] = [
                "shortcode": "IGSaveDemo", "owner": ["username": "igsave.studio", "is_private": false],
                "edge_sidecar_to_children": ["edges": nodes]
            ]
            let context = try! JSONSerialization.data(withJSONObject: ["gql_data": ["shortcode_media": node]])
            let wrapper = try! JSONSerialization.data(withJSONObject: ["contextJSON": String(decoding: context, as: UTF8.self)])
            data = Data("<script>init(\(String(decoding: wrapper, as: UTF8.self)))</script>".utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": isImage ? "image/png" : "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func artwork(_ alternate: Bool) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 720, height: 900)).pngData { renderer in
            let ctx = renderer.cgContext
            let top = alternate ? UIColor(red: 0.19, green: 0.30, blue: 0.43, alpha: 1)
                : UIColor(red: 0.59, green: 0.57, blue: 0.76, alpha: 1)
            let bottom = UIColor(red: 0.98, green: 0.77, blue: 0.66, alpha: 1)
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 720, y: 900), options: [])
            UIColor(red: 1, green: 0.89, blue: 0.73, alpha: 1).setFill()
            ctx.fillEllipse(in: CGRect(x: alternate ? 140 : 420, y: 160, width: 140, height: 140))
            for layer in 0..<3 {
                let path = UIBezierPath()
                let y = CGFloat(480 + layer * 130)
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(to: CGPoint(x: 720, y: y - 70),
                              controlPoint1: CGPoint(x: 240, y: y - 240),
                              controlPoint2: CGPoint(x: 490, y: y + 180))
                path.addLine(to: CGPoint(x: 720, y: 900))
                path.addLine(to: CGPoint(x: 0, y: 900))
                path.close()
                UIColor(red: 0.19 - Double(layer) * 0.045, green: 0.34 - Double(layer) * 0.065,
                        blue: 0.43 - Double(layer) * 0.075, alpha: 1).setFill()
                path.fill()
            }
        }
    }
}
#endif
