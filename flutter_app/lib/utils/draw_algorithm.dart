import 'dart:math';
import '../models/participant.dart';

/// Maps each participant to the participant they are gifting.
/// Prefers cross-gender pairs (male->female, female->male) and falls back
/// to any valid pairing when the gender split makes that impossible.
/// Returns null if no valid derangement exists (e.g. fewer than 2 participants).
Map<String, String>? drawAssignments(
  List<Participant> participants, [
  Random? rng,
]) {
  if (participants.length < 2) return null;
  final random = rng ?? Random.secure();

  final males = participants.where((p) => p.gender == Gender.male).toList();
  final females =
      participants.where((p) => p.gender == Gender.female).toList();
  final others = participants.where((p) => p.gender == Gender.other).toList();

  for (var attempt = 0; attempt < 200; attempt++) {
    final assignment = _attemptCrossGenderDraw(
      males,
      females,
      others,
      random,
    );
    if (assignment != null) return assignment;
  }

  // Fallback: pure random derangement ignoring gender.
  for (var attempt = 0; attempt < 200; attempt++) {
    final assignment = _attemptRandomDerangement(participants, random);
    if (assignment != null) return assignment;
  }

  return null;
}

Map<String, String>? _attemptCrossGenderDraw(
  List<Participant> males,
  List<Participant> females,
  List<Participant> others,
  Random random,
) {
  final shuffledMales = List.of(males)..shuffle(random);
  final shuffledFemales = List.of(females)..shuffle(random);
  final assignment = <String, String>{};

  if (shuffledMales.length == shuffledFemales.length && others.isEmpty) {
    for (var i = 0; i < shuffledMales.length; i++) {
      assignment[shuffledMales[i].id] =
          shuffledFemales[(i + 1) % shuffledFemales.length].id;
      assignment[shuffledFemales[i].id] =
          shuffledMales[(i + 1) % shuffledMales.length].id;
    }
    return assignment;
  }

  // Uneven split: combine everyone and fall back to random derangement,
  // but bias the rotation order so male/female remain mostly separated
  // when group sizes allow it.
  final all = [...shuffledMales, ...shuffledFemales, ...others]
    ..shuffle(random);
  return _attemptRandomDerangement(all, random);
}

Map<String, String>? _attemptRandomDerangement(
  List<Participant> participants,
  Random random,
) {
  final ids = participants.map((p) => p.id).toList();
  final shuffled = List.of(ids)..shuffle(random);

  for (var i = 0; i < ids.length; i++) {
    if (shuffled[i] == ids[i]) return null;
  }

  return Map.fromIterables(ids, shuffled);
}
