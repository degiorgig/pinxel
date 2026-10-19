import CoreGraphics

/// Piccola cache LRU per sfocature, pixelature e livelli già calcolati.
final class EffectCache {
    private var storage: [String: CGImage] = [:]
    private var order: [String] = []
    private let capacity: Int
    /// Quante immagini sono state calcolate (per i test).
    private(set) var misses = 0

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    func image(for key: String, make: () -> CGImage?) -> CGImage? {
        if let hit = storage[key] { return hit }
        misses += 1
        guard let value = make() else { return nil }
        storage[key] = value
        order.append(key)
        if order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
        return value
    }

    func removeAll() {
        storage.removeAll()
        order.removeAll()
    }
}
