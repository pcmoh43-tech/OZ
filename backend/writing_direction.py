"""Keep mixed Arabic/English text on one RTL host path."""

from __future__ import annotations

import re

LRI = "\u2066"
PDI = "\u2069"
RLM = "\u200f"
BIDI_MARKS = re.compile(r"[\u200e\u200f\u202a-\u202e\u2066-\u2069]")
LATIN_TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9+._/-]*")


def strip_bidi_marks(text: str | None) -> str:
    return BIDI_MARKS.sub("", text or "")


def isolate_embedded_latin(text: str | None) -> str:
    """Wrap Latin tokens in LRI…PDI and RLM so they cannot flip following Arabic."""
    source = strip_bidi_marks(text)
    return LATIN_TOKEN.sub(lambda match: f"{LRI}{match.group(0)}{PDI}{RLM}", source)


def visual_rtl_line(text: str | None) -> str:
    """Reshape and visually order one logical line with an RTL base direction."""
    isolated = isolate_embedded_latin(text)
    try:
        import arabic_reshaper

        reshaped = arabic_reshaper.reshape(isolated)
    except Exception:
        reshaped = isolated

    try:
        from bidi.algorithm import get_display

        try:
            return get_display(reshaped, base_dir="R")
        except TypeError:
            return get_display(reshaped)
    except Exception:
        return reshaped
