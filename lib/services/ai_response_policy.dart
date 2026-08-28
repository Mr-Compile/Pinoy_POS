/// Centralized policy and post-processor for all AI-generated natural
/// language responses in Pinoy POS.
///
/// This is the single source of truth for:
/// 1. The instruction given to the model (so it knows to produce plain,
///    humanized text).
/// 2. The deterministic sanitizer that removes any decorative Markdown the
///    model may still emit.
/// 3. The validator that re-checks the sanitized output before it is shown
///    to the user.
///
/// Every AI feature that produces conversational output must pass the raw
/// model response through [sanitize] and [isHumanized] before displaying it.
class AiResponsePolicy {
  AiResponsePolicy._();

  /// The authoritative instruction appended to the system prompt for every
  /// conversational AI request.  It tells the model to produce natural,
  /// plain-text, humanized responses and explicitly forbids decorative
  /// Markdown formatting.
  static const String instruction = '''

HUMANIZED RESPONSE POLICY (STRICT — MUST FOLLOW):

You are the Pinoy POS Virtual Assistant.  Respond like a natural, helpful virtual assistant — not like a documentation generator.

Tone and style:
- Be conversational, readable, direct, and human-friendly.
- Use simple language a small-business owner or staff member can understand quickly.
- Use Philippine business terms naturally when appropriate (sales, sukli, cash, GCash, bayad, inventory, stock, tindahan, daily sales, etc.).
- Do not force Filipino words into every response; use them only when they feel natural.

Formatting rules (CRITICAL):
- NEVER use Markdown formatting of any kind.
- NEVER use Markdown headings (#, ##, ###, ####).
- NEVER use bold formatting (**text**).
- NEVER use italic formatting (*text* or _text_).
- NEVER use horizontal rules (---, ***, ___).
- NEVER use strikethrough (~~text~~).
- NEVER use decorative code fences (``` or ~~~).
- NEVER use decorative backticks (`text`) for emphasis.
- NEVER surround words with repeated special characters such as **, ##, ---, ~~, or ```.
- NEVER create decorative response structures like headings followed by bullet lists.

Allowed plain text:
- You may use normal punctuation: periods, commas, question marks, exclamation points, colons, and hyphens inside words or ranges.
- You may use numbers, currency values like ₱1,250.50, dates like 2026-08-28, and product names like Coke-Zero or INV-2026-001.
- You may use line breaks to separate thoughts, but keep the response scannable and compact.

Conversational structure:
1. Give a short, direct answer first.
2. Add the most important supporting information.
3. Optionally end with one useful next step or offer.

Example of a GOOD response:
"Your sales today are ₱8,450 from 32 transactions. Chicken Adobo is your top-selling product with 14 units sold. Cash accounted for ₱5,200 while GCash accounted for ₱2,650. If you want, I can compare this with yesterday."

Examples of PROHIBITED responses:
- "## Sales Summary" or "## Today's Sales" — never use heading syntax.
- "**Total Sales:** ₱8,500" — never use bold markers.
- "---" — never use horizontal rules.
- Bullet lists starting with "* " or "- " — write as plain sentences or lines instead.
- "```" code fences — never use them.

Identity rules:
- You are an AI virtual assistant.  Do not pretend to be a human.
- Do not say you personally checked the store, were watching the store, or are a staff member.
- Say things like "I checked the sales recorded in your POS" or "I found 12 transactions today."

This policy is enforced by the application after you respond, but your output will be cleaner and more useful if you follow it from the start.
''';

  /// Removes decorative Markdown from [text] while preserving real content.
  ///
  /// The sanitizer is intentionally conservative: it strips formatting syntax
  /// but keeps the meaning, numbers, dates, currency, product names, IDs, and
  /// URLs intact.
  static String sanitize(String text) {
    if (text.isEmpty) return text;

    var result = text;

    // 1. Code fences (3 or more backticks or tildes, with optional language).
    //    Remove the fence lines and keep only the content between them.
    result = _removeCodeFences(result);

    // 2. Horizontal rules on their own line.  Must match a line that only
    //    contains three or more of -, *, or _ (with optional spaces).
    result = _replacePattern(result, r'^[\s]*(?:[-*_][\s]*){3,}[\s]*$', '',
        multiLine: true);

    // 3. ATX headings (# Heading, ## Heading, etc.).
    //    Only remove # at the start of a line, not # inside text.
    result = _replacePattern(result, r'^[\s]*#{1,6}\s+(.*)$', r'\1',
        multiLine: true);

    // 4. Bold: **text**.
    result = _replacePattern(result, r'\*\*(.+?)\*\*', r'\1');

    // 5. Italic: *text* or _text_.
    //    Avoid matching single * or _ used as list markers, which are handled
    //    later.  This pattern only matches when the delimiters wrap content
    //    without surrounding whitespace immediately next to them.
    result = _replacePattern(result, r'\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)',
        r'\1');
    result = _replacePattern(result, r'_(?![\s_])(.+?)(?<![\s_])_(?!_)',
        r'\1');

    // 6. Strikethrough: ~~text~~.
    result = _replacePattern(result, r'~~(.+?)~~', r'\1');

    // 7. Single backticks: `text`.
    result = _replacePattern(result, r'`(.+?)`', r'\1');

    // 8. Markdown list markers at the start of a line.
    //    Convert "- item", "* item", "+ item", or "1. item" to just "item".
    result = _replacePattern(result, r'^[\s]*(?:[-*+]|\d+\.)\s+(.*)$',
        r'\1', multiLine: true);

    // 9. Clean up leftover decorative punctuation and whitespace.
    result = result.replaceAll('**', '').replaceAll('~~', '');
    result = _collapseBlankLines(result);

    return result.trim();
  }

  /// Returns true when [text] appears to be free of prohibited Markdown
  /// formatting.  If false, the caller should re-run [sanitize] (or a stricter
  /// fallback) before displaying the text.
  static bool isHumanized(String text) {
    if (text.contains('**')) return false;
    if (text.contains('~~')) return false;
    if (text.contains('```')) return false;
    if (text.contains('~~~')) return false;

    // Markdown headings on their own line.
    if (RegExp(r'^[\s]*#{1,6}\s+', multiLine: true).hasMatch(text)) return false;

    // Horizontal rules on their own line.
    if (RegExp(r'^[\s]*(?:[-*_][\s]*){3,}[\s]*$', multiLine: true)
        .hasMatch(text)) {
      return false;
    }

    // Italic markers that are not part of a word (e.g. *text* or _text_).
    if (RegExp(r'(?<![\w\s])\*[^\s*].*?[^\s*]\*(?![\w\s])').hasMatch(text)) {
      return false;
    }

    return true;
  }

  /// Sanitizes [text] and, if [isHumanized] still fails, re-runs the
  /// sanitizer up to [maxPasses] times.  Returns the cleanest result.
  static String sanitizeAndValidate(String text, {int maxPasses = 3}) {
    var result = sanitize(text);
    for (var i = 0; i < maxPasses - 1; i++) {
      if (isHumanized(result)) break;
      result = sanitize(result);
    }
    return result.trim();
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static String _removeCodeFences(String text) {
    final lines = text.split('\n');
    final buffer = StringBuffer();
    var inFence = false;
    var fenceLen = 0;

    for (final line in lines) {
      final trimmed = line.trimLeft();
      final fenceMatch = RegExp(r'^(```+|~~~+)').firstMatch(trimmed);
      if (fenceMatch != null) {
        if (!inFence) {
          inFence = true;
          fenceLen = fenceMatch.group(0)!.length;
          continue;
        } else if (trimmed.length >= fenceLen) {
          inFence = false;
          fenceLen = 0;
          continue;
        }
      }
      if (!inFence) {
        buffer.writeln(line);
      } else {
        // Inside a fence: keep the raw content but do not include the
        // optional language tag line if it is the first fence line.
        buffer.writeln(line);
      }
    }

    // If the fence was never closed, still treat the remainder as content.
    return buffer.toString().trimRight();
  }

  static String _replacePattern(
    String text,
    String pattern,
    String replacement, {
    bool multiLine = false,
  }) {
    return text.replaceAllMapped(
      RegExp(pattern, multiLine: multiLine),
      (match) {
        if (match.groupCount >= 1 && match.group(1) != null) {
          return replacement.replaceAll(r'\1', match.group(1)!);
        }
        return replacement;
      },
    );
  }

  static String _collapseBlankLines(String text) {
    // Replace 3+ consecutive newlines with two, and trim each line's edges.
    return text
        .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
        .trim();
  }
}
