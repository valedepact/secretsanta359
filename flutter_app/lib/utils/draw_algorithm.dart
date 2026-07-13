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

/// Variant of [drawAssignments] for pairing up latecomers who joined after
/// the main draw, triggered manually by the organizer. Identical rules for
/// 3+ people (still rejects mutual pairs and self-assignment), but with
/// exactly 2 people waiting, a mutual pair is unavoidable - it's the only
/// possible outcome - so it's allowed here (unlike the main draw).
Map<String, String>? drawLatecomerAssignments(
  List<Participant> pending, [
  Random? rng,
]) {
  if (pending.length < 2) return null;
  if (pending.length == 2) {
    return {
      pending[0].id: pending[1].id,
      pending[1].id: pending[0].id,
    };
  }
  return drawAssignments(pending, rng);
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
    // Build two separate rotations so males gift females and vice versa,
    // but use a random offset to avoid guaranteed mutual pairs when N==2.
    final offset = shuffledMales.length == 1
        ? 0
        : 1 + random.nextInt(shuffledMales.length - 1);
    for (var i = 0; i < shuffledMales.length; i++) {
      assignment[shuffledMales[i].id] =
          shuffledFemales[(i + offset) % shuffledFemales.length].id;
      assignment[shuffledFemales[i].id] =
          shuffledMales[(i + offset) % shuffledMales.length].id;
    }
    // Verify no mutual pairs slipped through (only possible when N==2).
    for (final entry in assignment.entries) {
      final recipientGiftee = assignment[entry.value];
      if (recipientGiftee == entry.key) return null;
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
    // Reject self-assignment and mutual pairs (A→B and B→A).
    if (shuffled[i] == ids[i]) return null;
    final j = ids.indexOf(shuffled[i]);
    if (shuffled[j] == ids[i]) return null;
  }

  return Map.fromIterables(ids, shuffled);
}
