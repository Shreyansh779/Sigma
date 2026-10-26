import Foundation

// The album URI a CreativeWorkTemplateView page's controller carries. Swift reflection reads the named
// fields without depending on struct offsets or importing Spotify's modules; a changed shape yields nil, so
// the row simply does not appear. An episode page is the same template, so only a spotify:album: URI counts.
@objc(SGAlbumQueuePage)
final class SGAlbumQueuePage: NSObject {
    @objc static func albumURI(_ controller: AnyObject) -> String? {
        // The path proven on 9.1.90: template -> creativeWork -> uri.
        if let uri = value(reflecting: controller, path: ["template", "creativeWork", "uri"]) { return uri }
        // A different build may name the fields differently; find a spotify:album: URI shallowly instead.
        return search(controller, depth: 0)
    }

    private static func value(reflecting root: AnyObject, path: [String]) -> String? {
        var value: Any = root
        for field in path {
            guard let child = Mirror(reflecting: value).children.first(where: { $0.label == field }) else { return nil }
            value = child.value
        }
        return album(value)
    }

    private static func album(_ value: Any) -> String? {
        if let url = value as? URL, url.absoluteString.hasPrefix("spotify:album:") { return url.absoluteString }
        if let str = value as? String, str.hasPrefix("spotify:album:") { return str }
        return nil
    }

    private static func search(_ value: Any, depth: Int) -> String? {
        if let album = album(value) { return album }
        if depth > 4 { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = search(child.value, depth: depth + 1) { return found }
        }
        return nil
    }
}
