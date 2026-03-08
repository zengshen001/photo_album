class EventMatchCandidate {
  final int oldEventId;
  final int newIndex;
  final double score;
  final double timeScore;
  final double distanceScore;
  final double overlapScore;

  const EventMatchCandidate({
    required this.oldEventId,
    required this.newIndex,
    required this.score,
    required this.timeScore,
    required this.distanceScore,
    required this.overlapScore,
  });
}
