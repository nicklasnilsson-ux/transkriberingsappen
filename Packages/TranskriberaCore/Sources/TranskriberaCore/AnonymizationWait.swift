import Foundation

/// När visas "Anonymiserar…"? Bara när det faktiskt finns text som räknas fram.
/// En inspelning utan en enda replik (tyst eller tom) har inget att anonymisera;
/// då kommer det aldrig något resultat, och väntan skulle aldrig ta slut.
public enum AnonymizationWait {
    public static func isWaiting(segmentCount: Int, hasCurrentResult: Bool) -> Bool {
        segmentCount > 0 && !hasCurrentResult
    }
}
