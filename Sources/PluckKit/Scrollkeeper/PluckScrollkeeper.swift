import TablesideShared
import UniformTypeIdentifiers

extension ScrollkeeperBridgeConfiguration {
    /// How Pluck uses the Scrollkeeper bridge: it lists the titles with a PDF, or with an archive Scrollkeeper
    /// unpacks, which may hold some (as in the index Scrollkeeper hands Pluck), opens their PDFs, and asks for one
    /// title at a time.
    public static var pluck: ScrollkeeperBridgeConfiguration {
        let isPDF: @Sendable (UTType) -> Bool = { $0.conforms(to: .pdf) }
        var configuration = ScrollkeeperBridgeConfiguration(appKey: "pluck", lists: { $0.mayHold(isPDF) },
                                                            opens: isPDF)
        configuration.sendsOneRequestAtATime = true
        return configuration
    }
}
