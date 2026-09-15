import unittest

from writing_direction import isolate_embedded_latin, strip_bidi_marks


class IsolateEmbeddedLatinTests(unittest.TestCase):
    def test_mid_sentence_english_keeps_arabic_logical_order(self):
        source = "هذا test للنص الكامل"
        isolated = isolate_embedded_latin(source)
        self.assertLess(isolated.index("هذا"), isolated.index("test"))
        self.assertLess(isolated.index("test"), isolated.index("للنص"))
        self.assertEqual(strip_bidi_marks(isolated), source)

    def test_leading_english_does_not_reorder_following_arabic(self):
        source = "API هو الواجهة"
        isolated = isolate_embedded_latin(source)
        self.assertEqual(strip_bidi_marks(isolated), source)
        self.assertTrue(isolated.endswith("هو الواجهة"))

    def test_idempotent(self):
        source = "افتح PDF ثم احفظ"
        self.assertEqual(
            isolate_embedded_latin(isolate_embedded_latin(source)),
            isolate_embedded_latin(source),
        )


if __name__ == "__main__":
    unittest.main()
