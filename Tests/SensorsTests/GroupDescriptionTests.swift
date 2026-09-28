import Testing
@testable import Sensors

/// `SensorCatalog.description(for:)`: the text the Temperatures graph shows when
/// a series is hovered. Every label the catalog can produce must have one, or a
/// series would silently fall back to the placeholder.
@Suite("Group descriptions")
struct GroupDescriptionTests {
    /// Every label the catalog can put on a group: the CPU lists, the prefix
    /// groups, the shared keys, and the two names it defines itself.
    private var everyLabel: Set<String> {
        var labels = Set(SensorCatalog.prefixGroups.map(\.0))
        labels.formUnion(SensorCatalog.sharedKeys.map(\.0))
        labels.formUnion(SensorCatalog.chipCPUGroups.values.flatMap { $0.map(\.0) })
        labels.insert(SensorCatalog.cpuOverallGroupName)
        labels.insert(SensorCatalog.cpuFallbackGroupName)
        return labels
    }

    @Test func everyGroupTheCatalogNamesHasADescription() {
        let missing = everyLabel.subtracting(SensorCatalog.groupDescriptions.keys)
        #expect(missing.isEmpty)
    }

    @Test func everyDescriptionExplainsMoreThanTheLabel() {
        for label in everyLabel {
            let text = SensorCatalog.description(for: label)
            #expect(!text.isEmpty)
            #expect(text != label)
            #expect(text.count > label.count)
        }
    }

    /// The hints are for someone who owns the Mac, not for someone who knows the
    /// SMC key names. No key family, no protocol vocabulary.
    @Test func descriptionsStayFreeOfKeyNames() {
        let jargon = ["*", "SMC", "fourcc", "IOKit", "diode"]

        for (label, text) in SensorCatalog.groupDescriptions {
            for term in jargon {
                #expect(!text.localizedCaseInsensitiveContains(term), "\(label): \(term)")
            }
        }
    }

    /// An uncurated chip is grouped by prefix, so a label can turn up that this
    /// build has no text for; the graph must still say something.
    @Test func anUnknownGroupGetsThePlaceholder() {
        #expect(
            SensorCatalog.description(for: "No such group")
                == SensorCatalog.unknownGroupDescription
        )
        #expect(!SensorCatalog.unknownGroupDescription.isEmpty)
    }

    /// The two CPU labels are shared across chip generations, so a per-chip list
    /// cannot drift away from the text.
    @Test func theCPUDescriptionsCoverEveryGeneration() {
        let cpuLabels = Set(SensorCatalog.chipCPUGroups.values.flatMap { $0.map(\.0) })
        #expect(cpuLabels == ["CPU efficiency cores", "CPU performance cores", "CPU super cores"])
    }
}
