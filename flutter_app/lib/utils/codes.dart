import 'dart:math';

const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String generateCode(int length, [Random? rng]) {
  final random = rng ?? Random.secure();
  return List.generate(
    length,
    (_) => _codeChars[random.nextInt(_codeChars.length)],
  ).join();
}

String generateShareCode() => generateCode(8);
