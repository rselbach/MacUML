enum DiagramTemplate: String, CaseIterable, Identifiable {
    case blank
    case flowchart
    case sequence
    case classDiagram
    case state

    var id: Self { self }

    var title: String {
        switch self {
        case .blank:
            "Blank"
        case .flowchart:
            "Flowchart"
        case .sequence:
            "Sequence"
        case .classDiagram:
            "Class"
        case .state:
            "State"
        }
    }

    var source: String {
        switch self {
        case .blank:
            ""
        case .flowchart:
            """
            flowchart LR
                Troy[Start assignment] --> Abed{Ready to review?}
                Abed -->|Yes| Greendale[Share with Greendale]
                Abed -->|No| Troy
            """
        case .sequence:
            """
            sequenceDiagram
                participant Troy
                participant Abed
                participant Greendale as Greendale Community College

                Troy->>Abed: Send draft
                Abed-->>Troy: Review notes
                Troy->>Greendale: Publish diagram
            """
        case .classDiagram:
            """
            classDiagram
                class StudyGroup {
                    +String project
                    +review()
                }
                class Troy {
                    +present()
                }
                class Abed {
                    +document()
                }

                StudyGroup o-- Troy
                StudyGroup o-- Abed
            """
        case .state:
            """
            stateDiagram-v2
                [*] --> Draft
                Draft --> Review: Troy submits
                Review --> Published: Abed approves
                Review --> Draft: Needs changes
                Published --> [*]
            """
        }
    }
}
