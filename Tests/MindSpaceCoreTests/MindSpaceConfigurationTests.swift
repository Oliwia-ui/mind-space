import Testing
@testable import MindSpaceCore

@Test("native application identity is stable")
func nativeApplicationIdentityIsStable() {
    #expect(MindSpaceConfiguration.productName == "Mind Space")
    #expect(MindSpaceConfiguration.bundleIdentifier == "com.oliwia.mindspace")
    #expect(MindSpaceConfiguration.databaseFilename == "MindSpace.store")
}
