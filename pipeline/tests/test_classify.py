from nearby.sources.base import classify, parse_cost


def test_title_outranks_description():
    # The blurb says "open mic", but a poetry night is arts, not comedy.
    assert classify("Brushfire Poetry Night",
                    weak=["a monthly open mic for poets"]) == "arts"


def test_description_used_only_as_fallback():
    assert classify("Untitled Thing", weak=["a stand-up comedy showcase"]) == "comedy"


def test_default_applies_when_nothing_matches():
    assert classify("Your Arms Are My Cocoon", default="music") == "music"
    assert classify("Your Arms Are My Cocoon") == "other"


def test_parse_cost():
    assert parse_cost("$10") == (10.0, 10.0, False)
    assert parse_cost("$15 - $20") == (15.0, 20.0, False)
    assert parse_cost("Free") == (0.0, 0.0, True)
    assert parse_cost("no cover") == (0.0, 0.0, True)
    assert parse_cost(None) == (None, None, False)
    assert parse_cost("donations welcome") == (None, None, False)
