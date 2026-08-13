import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:insta_killer_domain/insta_killer_domain.dart';

/// Turns a challenge into the six digits the Guardian reads back.
///
/// HMAC-SHA256 truncated the way TOTP does it — a well-trodden construction rather than
/// something invented here.
///
/// **The honest limit of this scheme.** Both phones hold the same secret, because your
/// phone has to *verify* the response and cannot do that without it. Somebody determined,
/// with developer tools and a rooted device, could read it out and compute their own
/// codes. That is not the adversary this defends against: the adversary is you, later
/// tonight, wanting the quota raised now. Extracting a key is not something that happens
/// in a weak moment, and it is stated plainly in LIMITATIONS.md rather than glossed.
///
/// Public-key signing would remove that limit, and does not fit: a signature cannot be
/// truncated to six readable digits, so the Guardian would have to be in the same room to
/// scan a QR code — which defeats approving from somewhere else.
class HmacCodeSigner implements CodeSigner {
  const HmacCodeSigner(this.secret);

  final String secret;

  @override
  String sign(String challenge) {
    final mac = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(challenge.trim()));
    final bytes = mac.bytes;

    // Dynamic truncation (RFC 4226 §5.3): the last nibble picks where to read from, so
    // every byte of the digest can influence the output rather than only the first four.
    final offset = bytes[bytes.length - 1] & 0x0f;
    final binary = ((bytes[offset] & 0x7f) << 24) |
        ((bytes[offset + 1] & 0xff) << 16) |
        ((bytes[offset + 2] & 0xff) << 8) |
        (bytes[offset + 3] & 0xff);

    return (binary % 1000000).toString().padLeft(6, '0');
  }
}

/// The alphabet for a paired secret.
///
/// Crockford-ish: no I, L, O, U, 0 or 1. The secret gets read aloud or copied by hand
/// between two people, and every ambiguous glyph is a failed pairing and a support
/// conversation.
const String _alphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

/// A fresh shared secret, grouped for reading out: `K7P2-9XMF-3TQA-8HN5-2WRJ`.
///
/// Twenty characters of a thirty-symbol alphabet is a little under 100 bits, which is far
/// more than the six-digit codes it protects and costs nothing extra to type once.
String generateGuardianSecret({Random? random}) {
  // Random.secure by default. A predictable pairing secret would make every approval
  // code forgeable, which is the one thing this must not be.
  final rng = random ?? Random.secure();
  final chars = List.generate(20, (_) => _alphabet[rng.nextInt(_alphabet.length)]);

  return [
    for (var i = 0; i < 20; i += 4) chars.sublist(i, i + 4).join(),
  ].join('-');
}

/// Six digits for a challenge. Unpredictable so a challenge cannot be answered in advance.
String generateChallenge({Random? random}) {
  final rng = random ?? Random.secure();
  return List.generate(6, (_) => rng.nextInt(10)).join();
}

/// Accepts a secret typed with any spacing, casing or dashes.
///
/// Normalised before use so `k7p2 9xmf…` and `K7P2-9XMF-…` pair to the same secret — the
/// two phones must agree on the exact string or every code mismatches for a reason
/// neither person can see.
String normaliseSecret(String input) =>
    input.toUpperCase().replaceAll(RegExp('[^$_alphabet]'), '');

/// Whether [input] could be a secret at all, before we try to pair with it.
bool looksLikeSecret(String input) => normaliseSecret(input).length == 20;
