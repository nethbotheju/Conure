import XCTest
@testable import ConureCore

final class ModelStoreTests: XCTestCase {
    func testEngineRoutingAndCacheDirectories() {
        XCTAssertEqual(ModelStore.parakeet.engine, .speechSwift)
        XCTAssertEqual(ModelStore.sortformer.engine, .speechSwift)
        XCTAssertEqual(ModelStore.descriptor(for: ModelStore.unified.hfRepo)?.id, ModelStore.unified.id)
        XCTAssertEqual(ModelStore.descriptor(for: ModelStore.multilingual.id)?.engine, .fluidAudio)
        XCTAssertEqual(ModelStore.directory(for: ModelStore.unified).lastPathComponent, "parakeet-unified-en-0.6b")
        XCTAssertEqual(ModelStore.directory(for: ModelStore.multilingual).lastPathComponent, "parakeet-tdt-0.6b-v3")
        XCTAssertFalse(ModelStore.unified.isRequired)
        XCTAssertTrue(ModelStore.parakeet.isDefault)
    }
}
