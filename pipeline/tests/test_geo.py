from nearby.geo import bbox, haversine_m, miles


def test_known_distance_reno_to_stateline():
    # Downtown Reno to Stateline NV: about 42 miles as the crow flies.
    d = miles(haversine_m(39.5296, -119.8138, 38.9599, -119.9401))
    assert 39 < d < 45


def test_sacramento_is_outside_the_reno_radius():
    d = miles(haversine_m(39.5296, -119.8138, 38.5816, -121.4944))
    assert d > 100


def test_zero_distance():
    assert haversine_m(39.5, -119.8, 39.5, -119.8) == 0.0


def test_bbox_contains_center():
    lo_lat, lo_lon, hi_lat, hi_lon = bbox(39.5296, -119.8138, 100 * 1609.344)
    assert lo_lat < 39.5296 < hi_lat
    assert lo_lon < -119.8138 < hi_lon
