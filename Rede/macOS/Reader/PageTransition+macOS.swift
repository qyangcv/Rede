extension PageTransition {
    func makeTurner(reader: Reader) -> any PageTurner {
        switch self {
        case .none: InstantTurner(reader: reader)
        }
    }
}
