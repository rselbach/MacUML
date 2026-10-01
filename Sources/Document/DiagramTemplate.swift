enum DiagramTemplate: String, CaseIterable, Identifiable {
    case blank
    case flowchart
    case sequence
    case classDiagram
    case state
    case entityRelationship
    case gantt
    case pie
    case mindmap
    case timeline
    case gitGraph

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
        case .entityRelationship:
            "Entity Relationship"
        case .gantt:
            "Gantt"
        case .pie:
            "Pie"
        case .mindmap:
            "Mindmap"
        case .timeline:
            "Timeline"
        case .gitGraph:
            "Git Graph"
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
        case .entityRelationship:
            """
            erDiagram
                STUDY_GROUP ||--|{ STUDENT : "meets with"
                STUDENT }o--o{ COURSE : attends
                STUDENT {
                    string name "Troy Barnes"
                    string major
                }
                COURSE {
                    string title "Spanish 101"
                }
            """
        case .gantt:
            """
            gantt
                title Greendale Paintball Prep
                dateFormat YYYY-MM-DD
                section Planning
                    Troy scouts the campus :scout, 2026-03-02, 3d
                    Abed films the trailer :after scout, 2d
                section Game
                    Paintball tournament :2026-03-09, 1d
            """
        case .pie:
            """
            pie title Study Room F Snacks
                "Troy's popcorn" : 45
                "Abed's pudding" : 30
                "Shirley's brownies" : 25
            """
        case .mindmap:
            """
            mindmap
                root((Greendale))
                    Study Group
                        Troy
                        Abed
                    Clubs
                        Glee
                        Air Conditioning Repair
            """
        case .timeline:
            """
            timeline
                title Troy and Abed at Greendale
                Year 1 : Spanish project
                Year 2 : Paintball
                Year 3 : Dreamatorium
            """
        case .gitGraph:
            """
            gitGraph
                commit id: "Outline"
                branch troy
                checkout troy
                commit id: "Troy draft"
                checkout main
                branch abed
                commit id: "Abed storyboard"
                checkout main
                merge troy
                merge abed
            """
        }
    }
}
