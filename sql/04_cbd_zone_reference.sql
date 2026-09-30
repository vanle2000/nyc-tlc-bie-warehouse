-- =====================================================================
-- 04_cbd_zone_reference.sql
-- Derive the Congestion Relief Zone (Manhattan at or below 60th Street)
-- treated-zone set FROM the TLC zone lookup, rather than hard-coding IDs.
--
-- The CBD toll (effective 2025-01-05) applies to Manhattan local streets
-- at or below 60th St. The TLC zone lookup does not carry a street-level
-- boundary column, so we build the treated set from the Manhattan zones
-- whose neighborhoods lie in that area. This list is REVIEWABLE and
-- editable -- it is an explicit modeling decision, documented here, not a
-- magic set of numbers buried in code.
--
-- Method:
--   1. Start from Borough = 'Manhattan'.
--   2. Include the zones for neighborhoods at/below 60th St (Midtown down
--      to the Financial District / Battery, plus the relevant edges).
--   3. EXCLUDE the always-exempt through-routes noted by the MTA
--      (FDR Drive, West Side Highway) where they appear as distinct zones.
--   4. Everything else is control.
--
-- Verify the resulting zone list against the TLC Manhattan zone map before
-- publishing; treat this as the analyst's documented boundary call.
-- =====================================================================

-- Candidate treated zones: Manhattan neighborhoods at/below ~60th Street.
-- (Names matched from the zone lookup's Zone column.)
CREATE OR REPLACE VIEW nyc_tlc.cbd_zone_ref AS
SELECT
    LocationID AS location_id,
    Borough    AS borough,
    Zone       AS zone,
    service_zone,
    CASE
        WHEN Borough = 'Manhattan' AND Zone IN (
            -- Midtown / Times Sq / Theatre area
            'Midtown Center','Midtown East','Midtown North','Midtown South',
            'Times Sq/Theatre District','Garment District','Clinton East','Clinton West',
            -- Murray Hill / Kips Bay / Gramercy / Flatiron / Union Sq
            'Murray Hill','Kips Bay','Gramercy','Flatiron','Union Sq',
            -- Chelsea / Hells Kitchen area edges below 60th
            'East Chelsea','West Chelsea/Hudson Yards','Hudson Sq',
            -- Village / SoHo / Little Italy / Chinatown
            'Greenwich Village North','Greenwich Village South','West Village',
            'East Village','SoHo','Little Italy/NoLiTa','Chinatown','Two Bridges/Seward Park',
            -- Lower East Side / Lower Manhattan
            'Lower East Side','Financial District North','Financial District South',
            'World Trade Center','Battery Park','Battery Park City','Seaport',
            'TriBeCa/Civic Center','Stuy Town/Peter Cooper Village','Meatpacking/West Village West',
            -- Midtown-adjacent below 60th
            'Sutton Place/Turtle Bay North','UN/Turtle Bay South','Park Ave South',
            'Penn Station/Madison Sq West'
        ) THEN 1
        ELSE 0
    END AS is_cbd
FROM nyc_tlc.raw_zone_lookup;

-- Inspect the treated set before trusting it downstream.
SELECT location_id, zone
FROM nyc_tlc.cbd_zone_ref
WHERE is_cbd = 1
ORDER BY zone;

-- How many zones are treated vs control (sanity check on the boundary call).
SELECT is_cbd, COUNT(*) AS zones
FROM nyc_tlc.cbd_zone_ref
GROUP BY is_cbd;
