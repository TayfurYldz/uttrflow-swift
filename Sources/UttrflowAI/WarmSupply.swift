// One prepared thing kept ready for whoever asks next, and made again as soon as one is taken.

/// Keeps something expensive ready before it is needed, so only the first asker pays for making it.
actor WarmSupply<Prepared: Sendable> {
    /// Makes one, prepared as far as it can be before the request that will use it.
    private let make: @Sendable (String) -> Prepared

    /// The one made ahead of time, if any.
    private var ready: Prepared?

    /// What `ready` was made for; a request carrying anything else cannot use it.
    private var madeFor: String?

    init(make: @escaping @Sendable (String) -> Prepared) {
        self.make = make
    }

    /// Keeps one for the next request carrying `key`, dropping any earlier one.
    func keep(_ prepared: Prepared, for key: String) {
        ready = prepared
        madeFor = key
    }

    /// The one kept for `key`, handed out once; a request for anything else empties the slot instead.
    func take(for key: String) -> Prepared? {
        defer { ready = nil }
        guard madeFor == key else {
            madeFor = nil
            return nil
        }
        return ready
    }

    /// Makes the next one, so a second and third request pay no more than the first did.
    func replenish(for key: String) {
        guard ready == nil || madeFor != key else { return }
        ready = make(key)
        madeFor = key
    }

    /// Whether one is waiting for `key` right now, which is what the supply exists to keep true.
    func isReady(for key: String) -> Bool { ready != nil && madeFor == key }
}
