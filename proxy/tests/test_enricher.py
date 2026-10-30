from PIL import Image

from app.providers.enricher import SparkEnricher, on_white, parse_enrichment


def test_parses_a_full_reply() -> None:
    reply = """```json
    {"type": "receipt", "ocr_text": "Cafe Lumiere 09:42", "entities": {"date": "2026-03-14", "place": "Cafe Lumiere",
     "colour": "brown"}, "tags": ["Coffee", "cafe", "coffee"], "mood": ["cozy"], "description": "A faded receipt."}
    ```"""

    result = parse_enrichment(reply)

    assert result.type == "receipt"
    assert result.ocr_text == "Cafe Lumiere 09:42"
    assert result.entities == {"date": "2026-03-14", "place": "Cafe Lumiere"}  # unknown keys dropped
    assert result.tags == ("coffee", "cafe")  # lower-cased and deduped
    assert result.mood == ("cozy",)


def test_garbage_reply_gives_empty_enrichment() -> None:
    result = parse_enrichment("I think this is a receipt!")

    assert result.type == "other" and result.ocr_text == "" and result.tags == ()


def test_unknown_type_and_wrong_field_types_are_tolerated() -> None:
    result = parse_enrichment('{"type": "spaceship", "ocr_text": 42, "tags": "coffee", "mood": [1, "calm"]}')

    assert result.type == "other"
    assert result.ocr_text == ""
    assert result.tags == ()
    assert result.mood == ("calm",)


def test_transparent_scraps_are_sent_on_white() -> None:
    scrap = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    scrap.paste((200, 0, 0, 255), (2, 2, 8, 8))
    sent: list[Image.Image] = []

    def transport(system: str, text: str, image: Image.Image) -> str:
        sent.append(image)
        return '{"type": "sticker"}'

    SparkEnricher(transport).enrich(scrap)

    assert sent[0].mode == "RGB"
    assert sent[0].getpixel((0, 0)) == (255, 255, 255)
    assert sent[0].getpixel((5, 5)) == (200, 0, 0)
    assert on_white(Image.new("RGB", (2, 2))).mode == "RGB"
