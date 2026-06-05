import Foundation
import Testing
@testable import OperatorDesktop

@Test func repositorySettingsAccessibilityLabelsIncludeRepositoryName() {
    let repository = OperatorRepository(
        id: UUID(),
        name: "operator",
        path: "/tmp/operator",
        defaultBranch: "main",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(
        RepositorySettingsAccessibility.defaultBranchLabel(for: repository)
            == "Default branch for operator"
    )
    #expect(
        RepositorySettingsAccessibility.saveDefaultBranchLabel(for: repository)
            == "Save default branch for operator"
    )
}
