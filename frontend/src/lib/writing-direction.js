/** Invisible Unicode used to keep mixed text on one host direction. */
export const LRI = "\u2066"; // Left-to-Right Isolate
export const RLI = "\u2067"; // Right-to-Left Isolate
export const FSI = "\u2068"; // First Strong Isolate
export const PDI = "\u2069"; // Pop Directional Isolate
export const RLM = "\u200F"; // Right-to-Left Mark
export const LRM = "\u200E"; // Left-to-Right Mark

const BIDI_MARKS = /[\u200E\u200F\u202A-\u202E\u2066-\u2069]/g;
const LATIN_TOKEN = /[A-Za-z][A-Za-z0-9+._/-]*/g;

export function isBidiMark(ch) {
  if (!ch) return false;
  const code = ch.charCodeAt(0);
  return (
    code === 0x200e ||
    code === 0x200f ||
    (code >= 0x202a && code <= 0x202e) ||
    (code >= 0x2066 && code <= 0x2069)
  );
}

export function stripBidiMarks(text) {
  return String(text ?? "").replace(BIDI_MARKS, "");
}

/**
 * Wrap each English/Latin token in LRI…PDI and follow with RLM so Arabic
 * after it stays on the RTL host path instead of flipping to LTR.
 */
export function isolateEmbeddedLatin(text) {
  const source = stripBidiMarks(text);
  return source.replace(
    LATIN_TOKEN,
    (token) => `${LRI}${token}${PDI}${RLM}`
  );
}

export function splitForHostDisplay(text) {
  const source = stripBidiMarks(text);
  const parts = [];
  const re = new RegExp(LATIN_TOKEN.source, "g");
  let lastIndex = 0;
  let match;
  while ((match = re.exec(source)) !== null) {
    if (match.index > lastIndex) {
      parts.push({ kind: "host", value: source.slice(lastIndex, match.index) });
    }
    parts.push({ kind: "latin", value: match[0] });
    lastIndex = match.index + match[0].length;
  }
  if (lastIndex < source.length) {
    parts.push({ kind: "host", value: source.slice(lastIndex) });
  }
  if (parts.length === 0 && source) {
    parts.push({ kind: "host", value: source });
  }
  return parts;
}

export function visibleIndex(text, rawIndex) {
  const value = String(text ?? "");
  const limit = Math.max(0, Math.min(rawIndex ?? 0, value.length));
  let visible = 0;
  for (let i = 0; i < limit; i += 1) {
    if (!isBidiMark(value[i])) visible += 1;
  }
  return visible;
}

export function rawIndexFromVisible(text, targetVisible) {
  const value = String(text ?? "");
  if (targetVisible <= 0) {
    let i = 0;
    while (i < value.length && isBidiMark(value[i])) i += 1;
    return i;
  }
  let visible = 0;
  for (let i = 0; i < value.length; i += 1) {
    if (!isBidiMark(value[i])) {
      if (visible === targetVisible) return i;
      visible += 1;
    }
  }
  return value.length;
}

/** Place the caret after a closing isolate so following Arabic is not captured. */
export function caretRawIndex(wrapped, targetVisible) {
  let index = rawIndexFromVisible(wrapped, targetVisible);
  while (
    index < wrapped.length &&
    (wrapped[index] === PDI || wrapped[index] === RLM)
  ) {
    index += 1;
  }
  return index;
}

export function applyHostDirection(text, selectionStart, selectionEnd) {
  const wrapped = isolateEmbeddedLatin(text);
  const startVisible = visibleIndex(text, selectionStart);
  const endVisible = visibleIndex(text, selectionEnd ?? selectionStart);
  return {
    text: wrapped,
    selectionStart: caretRawIndex(wrapped, startVisible),
    selectionEnd: caretRawIndex(wrapped, endVisible),
  };
}
