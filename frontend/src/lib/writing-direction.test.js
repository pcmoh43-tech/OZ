import {
  applyHostDirection,
  caretRawIndex,
  isolateEmbeddedLatin,
  LRI,
  PDI,
  RLM,
  splitForHostDisplay,
  stripBidiMarks,
  visibleIndex,
} from "./writing-direction";

describe("isolateEmbeddedLatin", () => {
  test("keeps Arabic logical order when wrapping a mid-sentence English word", () => {
    const source = "هذا test للنص الكامل";
    const isolated = isolateEmbeddedLatin(source);

    expect(isolated.indexOf("هذا")).toBeLessThan(isolated.indexOf("test"));
    expect(isolated.indexOf("test")).toBeLessThan(isolated.indexOf("للنص"));
    expect(isolated).toBe(`هذا ${LRI}test${PDI}${RLM} للنص الكامل`);
  });

  test("does not let a leading English token reorder the following Arabic", () => {
    const source = "API هو الواجهة";
    const isolated = isolateEmbeddedLatin(source);
    const stripped = stripBidiMarks(isolated);

    expect(stripped).toBe(source);
    expect(isolated.startsWith(`${LRI}API${PDI}${RLM}`)).toBe(true);
    expect(isolated.endsWith("هو الواجهة")).toBe(true);
  });

  test("is idempotent", () => {
    const source = "افتح PDF ثم احفظ";
    expect(isolateEmbeddedLatin(isolateEmbeddedLatin(source))).toBe(
      isolateEmbeddedLatin(source)
    );
  });
});

describe("splitForHostDisplay", () => {
  test("splits Latin islands from the Arabic host", () => {
    expect(splitForHostDisplay("سجل Whisper المحلي")).toEqual([
      { kind: "host", value: "سجل " },
      { kind: "latin", value: "Whisper" },
      { kind: "host", value: " المحلي" },
    ]);
  });
});

describe("caret mapping", () => {
  test("places the caret after PDI/RLM at the end of an English token", () => {
    const wrapped = isolateEmbeddedLatin("قبل hello بعد");
    const visibleEndOfHello =
      visibleIndex(wrapped, wrapped.indexOf("o") + 1);
    const caret = caretRawIndex(wrapped, visibleEndOfHello);

    expect(wrapped.slice(caret)).toBe(" بعد");
  });

  test("applyHostDirection preserves the visible caret", () => {
    const source = "مرحبا hello";
    const { text, selectionStart } = applyHostDirection(
      source,
      source.length,
      source.length
    );
    expect(stripBidiMarks(text.slice(0, selectionStart))).toBe(source);
  });
});
