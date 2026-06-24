import Foundation

struct WorkspaceCodemapAutomaticSelectionSourceIdentity: Hashable {
    let rootEpoch: WorkspaceCodemapRootEpoch
    let fileID: UUID
    let catalogGeneration: UInt64
}

struct WorkspaceCodemapAutomaticSelectionTarget: Hashable {
    let rootEpoch: WorkspaceCodemapRootEpoch
    let fileID: UUID
    let catalogGeneration: UInt64
    let requestGeneration: UInt64
    let logicalPath: WorkspaceCodemapLogicalPresentationPath
}

enum WorkspaceCodemapAutomaticSelectionSourceIssue: Equatable {
    case outsideRootScope(WorkspaceCodemapAutomaticSelectionSourceIdentity)
    case notCataloged(WorkspaceCodemapAutomaticSelectionSourceIdentity)
    case notDemanded(WorkspaceCodemapAutomaticSelectionSourceIdentity)
    case pending(
        WorkspaceCodemapAutomaticSelectionSourceIdentity,
        WorkspaceCodemapArtifactDemandTicket
    )
    case unavailable(
        WorkspaceCodemapAutomaticSelectionSourceIdentity,
        WorkspaceCodemapArtifactDemandUnavailableReason
    )
    case staleCatalogGeneration(
        WorkspaceCodemapAutomaticSelectionSourceIdentity,
        currentCatalogGeneration: UInt64?
    )
}

enum WorkspaceCodemapAutomaticSelectionTargetIssue: Equatable {
    case notCataloged(rootEpoch: WorkspaceCodemapRootEpoch, fileID: UUID)
    case staleGeneration(
        rootEpoch: WorkspaceCodemapRootEpoch,
        fileID: UUID,
        requestGeneration: UInt64
    )
    case logicalPathUnavailable(rootEpoch: WorkspaceCodemapRootEpoch, fileID: UUID)
}

enum WorkspaceCodemapAutomaticSelectionPartialReason: Equatable {
    case graph(WorkspaceCodemapStoreSelectionGraphPartialReason)
    case source(WorkspaceCodemapAutomaticSelectionSourceIssue)
    case target(WorkspaceCodemapAutomaticSelectionTargetIssue)
    case candidateUniverseIncomplete(
        rootEpoch: WorkspaceCodemapRootEpoch,
        missingContributionCount: Int
    )
    case candidateTerminal(
        rootEpoch: WorkspaceCodemapRootEpoch,
        fileID: UUID,
        reason: WorkspaceCodemapArtifactDemandUnavailableReason
    )
    case sourceDemandTimedOut(WorkspaceCodemapAutomaticSelectionSourceIdentity)
    case candidateDemandTimedOut(rootEpoch: WorkspaceCodemapRootEpoch, fileID: UUID)
}

enum WorkspaceCodemapAutomaticSelectionPendingReason: Equatable {
    case sourceDemand(
        WorkspaceCodemapAutomaticSelectionSourceIdentity,
        WorkspaceCodemapArtifactDemandTicket
    )
    case sourceBusy(WorkspaceCodemapAutomaticSelectionSourceIdentity, attempts: Int)
    case candidateDemand(
        rootEpoch: WorkspaceCodemapRootEpoch,
        fileID: UUID,
        ticket: WorkspaceCodemapArtifactDemandTicket
    )
    case candidateBusy(rootEpoch: WorkspaceCodemapRootEpoch, fileID: UUID, attempts: Int)
    case manifestAdmission(rootEpoch: WorkspaceCodemapRootEpoch)
    case graphRebuild(rootEpoch: WorkspaceCodemapRootEpoch)
}

enum WorkspaceCodemapAutomaticSelectionUnavailableReason: Equatable {
    case noReadySources
    case graph(WorkspaceCodemapStoreSelectionGraphQueryUnavailableReason)
}

enum WorkspaceCodemapAutomaticSelectionStaleReason: Equatable {
    case rootEpochNotCurrent(WorkspaceCodemapRootEpoch)
    case rootScopeChanged(WorkspaceCodemapRootEpoch)
    case sourceStateChanged(WorkspaceCodemapAutomaticSelectionSourceIdentity)
    case sourceCatalogGeneration(
        WorkspaceCodemapAutomaticSelectionSourceIdentity,
        currentCatalogGeneration: UInt64?
    )
    case graph(WorkspaceCodemapStoreSelectionGraphQueryStaleReason)
    case publicationReceipt
}

enum WorkspaceCodemapAutomaticSelectionBudgetReason: Equatable {
    case sourceLimit(attempted: Int, limit: Int)
    case uniqueSourceLimit(attempted: Int, limit: Int)
    case sourceIssueLimit(attempted: Int, limit: Int)
    case rootLimit(attempted: Int, limit: Int)
    case candidateUniverseLimit(attempted: Int, limit: Int)
    case candidateDemandLimit(attempted: Int, limit: Int)
    case targetLimit(attempted: Int, limit: Int)
    case resolutionLimit(attempted: Int, limit: Int)
    case referenceFailureLimit(attempted: Int, limit: Int)
    case byteLimit(attempted: Int, limit: Int)
    case accountingOverflow
    case graph(
        rootEpoch: WorkspaceCodemapRootEpoch,
        reason: WorkspaceCodemapStoreSelectionGraphQueryBudgetReason
    )
}

enum WorkspaceCodemapAutomaticSelectionCoverage: Equatable {
    case complete
    case partial([WorkspaceCodemapAutomaticSelectionPartialReason])
    case pending([WorkspaceCodemapAutomaticSelectionPendingReason])
    case unavailable(WorkspaceCodemapAutomaticSelectionUnavailableReason)
    case stale(WorkspaceCodemapAutomaticSelectionStaleReason)
    case busy(WorkspaceCodemapStoreSelectionGraphQueryBusyReason)
    case budget(WorkspaceCodemapStoreSelectionGraphQueryBudgetReason)
}

enum WorkspaceCodemapAutomaticSelectionAggregateCoverage: Equatable {
    case complete
    case partial([WorkspaceCodemapAutomaticSelectionPartialReason])
    case pending([WorkspaceCodemapAutomaticSelectionPendingReason])
    case unavailable(WorkspaceCodemapAutomaticSelectionUnavailableReason)
    case stale(WorkspaceCodemapAutomaticSelectionStaleReason)
    case busy(WorkspaceCodemapStoreSelectionGraphQueryBusyReason)
    case budget(WorkspaceCodemapAutomaticSelectionBudgetReason)
}

struct WorkspaceCodemapAutomaticSelectionRootResult: Equatable {
    let rootEpoch: WorkspaceCodemapRootEpoch
    let targets: [WorkspaceCodemapAutomaticSelectionTarget]
    let sourceIssues: [WorkspaceCodemapAutomaticSelectionSourceIssue]
    let targetIssues: [WorkspaceCodemapAutomaticSelectionTargetIssue]
    let coverage: WorkspaceCodemapAutomaticSelectionCoverage
    let graphTargetCount: Int
    let graphResolutionCount: Int
    let graphReferenceFailureCount: Int
    let graphByteCount: Int
    let graphKey: WorkspaceCodemapSelectionGraphRuntimeKey?

    init(
        rootEpoch: WorkspaceCodemapRootEpoch,
        targets: [WorkspaceCodemapAutomaticSelectionTarget],
        sourceIssues: [WorkspaceCodemapAutomaticSelectionSourceIssue],
        targetIssues: [WorkspaceCodemapAutomaticSelectionTargetIssue],
        coverage: WorkspaceCodemapAutomaticSelectionCoverage,
        graphTargetCount: Int = 0,
        graphResolutionCount: Int = 0,
        graphReferenceFailureCount: Int = 0,
        graphByteCount: Int = 0,
        graphKey: WorkspaceCodemapSelectionGraphRuntimeKey? = nil
    ) {
        self.rootEpoch = rootEpoch
        self.targets = targets
        self.sourceIssues = sourceIssues
        self.targetIssues = targetIssues
        self.coverage = coverage
        self.graphTargetCount = graphTargetCount
        self.graphResolutionCount = graphResolutionCount
        self.graphReferenceFailureCount = graphReferenceFailureCount
        self.graphByteCount = graphByteCount
        self.graphKey = graphKey
    }
}

struct WorkspaceCodemapAutomaticSelectionPublicationReceipt: Equatable {
    let requestID: UUID
    let rootScope: WorkspaceLookupRootScope
    let sourceTickets: [WorkspaceCodemapArtifactDemandTicket]
    let graphKeys: [WorkspaceCodemapSelectionGraphRuntimeKey]
    let targets: [WorkspaceCodemapAutomaticSelectionTarget]
}

enum WorkspaceCodemapAutomaticSelectionPublicationDisposition: Equatable {
    case current([WorkspaceCodemapAutomaticSelectionTarget])
    case stale(WorkspaceCodemapAutomaticSelectionStaleReason)
}

struct WorkspaceCodemapAutomaticSelectionCandidatePlan: Equatable {
    let candidates: [WorkspaceCodemapBindingAutomaticSelectionCatalogCandidate]
    let partialReasons: [WorkspaceCodemapAutomaticSelectionPartialReason]
}

enum WorkspaceCodemapAutomaticSelectionCandidatePlanDisposition: Equatable {
    case ready(WorkspaceCodemapAutomaticSelectionCandidatePlan)
    case pending([WorkspaceCodemapAutomaticSelectionPendingReason])
    case unavailable(WorkspaceCodemapAutomaticSelectionUnavailableReason)
    case stale(WorkspaceCodemapAutomaticSelectionStaleReason)
    case budget(WorkspaceCodemapAutomaticSelectionBudgetReason)
}

struct WorkspaceCodemapAutomaticSelectionResult: Equatable {
    let roots: [WorkspaceCodemapAutomaticSelectionRootResult]
    let aggregateCoverage: WorkspaceCodemapAutomaticSelectionAggregateCoverage
    let publicationReceipt: WorkspaceCodemapAutomaticSelectionPublicationReceipt?

    init(
        roots: [WorkspaceCodemapAutomaticSelectionRootResult],
        aggregateCoverage: WorkspaceCodemapAutomaticSelectionAggregateCoverage? = nil,
        publicationReceipt: WorkspaceCodemapAutomaticSelectionPublicationReceipt? = nil
    ) {
        self.roots = roots
        self.aggregateCoverage = aggregateCoverage ?? Self.aggregateCoverage(for: roots)
        self.publicationReceipt = publicationReceipt
    }

    var targets: [WorkspaceCodemapAutomaticSelectionTarget] {
        switch aggregateCoverage {
        case .complete, .partial:
            roots.flatMap(\.targets)
        case .pending, .unavailable, .stale, .busy, .budget:
            []
        }
    }

    private static func aggregateCoverage(
        for roots: [WorkspaceCodemapAutomaticSelectionRootResult]
    ) -> WorkspaceCodemapAutomaticSelectionAggregateCoverage {
        var partial: [WorkspaceCodemapAutomaticSelectionPartialReason] = []
        for root in roots {
            switch root.coverage {
            case .complete:
                continue
            case let .partial(reasons):
                partial.append(contentsOf: reasons)
            case let .pending(reasons):
                return .pending(reasons)
            case let .unavailable(reason):
                return .unavailable(reason)
            case let .stale(reason):
                return .stale(reason)
            case let .busy(reason):
                return .busy(reason)
            case let .budget(reason):
                return .budget(.graph(rootEpoch: root.rootEpoch, reason: reason))
            }
        }
        return partial.isEmpty ? .complete : .partial(partial)
    }
}
