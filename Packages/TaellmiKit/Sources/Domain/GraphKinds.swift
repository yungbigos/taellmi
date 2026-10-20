/// The node and edge kinds the pipeline depends on (ADR 0005). Their rows live in config and can be
/// renamed or restyled there, but never deleted. Every other kind is pure config.
public enum GraphKinds {
    public static let entry = "entry"
    public static let fragment = "fragment"
    public static let atom = "atom"
    public static let concept = "concept"
    public static let cluster = "cluster"
    /// A generated one-sentence summary of an Entry (ADR 0012).
    public static let summary = "summary"

    /// A part contained in a whole: Entry → Fragment, Fragment → Atom.
    public static let contains = "contains"
    /// Words that refer to a Concept: Fragment or Atom → Concept.
    public static let mentions = "mentions"
    /// Concepts that appear together.
    public static let coOccurs = "co_occurs"
    /// Fragments that are close in meaning.
    public static let similar = "similar"
    /// Membership in a Cluster.
    public static let memberOf = "member_of"
    /// A connection made by hand (a Link).
    public static let link = "link"

    public static let systemNodeKinds: Set<String> = [entry, fragment, atom, concept, cluster, summary]
    public static let systemEdgeKinds: Set<String> = [contains, mentions, coOccurs, similar, memberOf, link]
}
