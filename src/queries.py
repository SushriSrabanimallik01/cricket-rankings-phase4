"""queries.py - every READ operation of the application (raw SQL, %s parameters).

Filtering, joining, ranking and aggregation all happen inside MySQL.
Phase 1 operation IDs (S1, P1, A1, Q1, H1, R1 ...) are noted on each function.
"""
from database import query_all, query_one

FORMATS = ("Test", "ODI", "T20I")
GENDERS = ("Men", "Women")

# Column names cannot be sent as parameters, so the three player lists are
# chosen from this fixed whitelist (never from user text).
PLAYER_LISTS = {
    "batting":    ("BattingPoints",   "BattingRank"),
    "bowling":    ("BowlingPoints",   "BowlingRank"),
    "allrounder": ("AllRounderIndex", "AllRounderRank"),
}


def like_pattern(text):
    """'%text%' with LIKE wildcards in the user's text escaped; None if empty."""
    text = (text or "").strip()
    if not text:
        return None
    text = text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return "%" + text + "%"


# ------------------------ dropdown helpers ---------------------------
def all_teams():
    return query_all("SELECT ICC_Code, TeamName FROM Team ORDER BY TeamName")


def all_venues():
    return query_all("SELECT VenueID, VenueName, City, Country FROM Venue ORDER BY Country, City, VenueName")


def all_series():
    return query_all("SELECT SeriesID, SeriesName, Gender, Format, StartDate, EndDate "
                     "FROM Series ORDER BY StartDate DESC")


def all_players():
    return query_all("SELECT PlayerID, FirstName, LastName, Gender, ICC_Code "
                     "FROM Player ORDER BY LastName, FirstName")


def list_countries():
    return query_all("SELECT DISTINCT Country FROM Venue ORDER BY Country")


# ------------------------------ S: selection -------------------------
def list_teams(fmt=None):
    """S1 Team directory: complete team rows, optionally only teams eligible for a format.
    Also shows the derived SquadSize."""
    return query_all(
        "SELECT t.ICC_Code, t.TeamName, t.EligibleFormat1, t.EligibleFormat2, t.EligibleFormat3, "
        "       (SELECT COUNT(*) FROM Player p WHERE p.ICC_Code = t.ICC_Code) AS SquadSize "
        "FROM Team t "
        "WHERE (%s IS NULL OR %s IN (t.EligibleFormat1, t.EligibleFormat2, t.EligibleFormat3)) "
        "ORDER BY t.TeamName",
        (fmt, fmt))


def get_team(code):
    return query_one(
        "SELECT t.ICC_Code, t.TeamName, t.EligibleFormat1, t.EligibleFormat2, t.EligibleFormat3, "
        "       (SELECT COUNT(*) FROM Player p WHERE p.ICC_Code = t.ICC_Code) AS SquadSize "
        "FROM Team t WHERE t.ICC_Code = %s", (code,))


def series_matches(series_id):
    """S2 Series fixture list: every match of a series in date order, with venue,
    teams, winner/result and subclass details."""
    return query_all(
        "SELECT m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, "
        "       v.VenueName, v.City, tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied, "
        "       GROUP_CONCAT(t.TeamName ORDER BY t.TeamName SEPARATOR ' vs ') AS Teams, "
        "       MAX(CASE WHEN c.Outcome = 'Win' THEN t.TeamName END) AS Winner, "
        "       MAX(CASE WHEN c.Outcome IN ('Tie','Draw','NoResult') THEN c.Outcome END) AS OtherResult "
        "FROM CricketMatch m "
        "JOIN Venue v ON v.VenueID = m.VenueID "
        "LEFT JOIN TestMatch tm ON tm.MatchID = m.MatchID "
        "LEFT JOIN LimitedOversMatch lom ON lom.MatchID = m.MatchID "
        "LEFT JOIN Contests c ON c.MatchID = m.MatchID "
        "LEFT JOIN Team t ON t.ICC_Code = c.ICC_Code "
        "WHERE m.SeriesID = %s "
        "GROUP BY m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, "
        "         v.VenueName, v.City, tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied "
        "ORDER BY m.StartDate, m.MatchID",
        (series_id,))


def squad(code):
    """S3 Squad page: complete rows of the players who currently represent a team."""
    return query_all(
        "SELECT p.PlayerID, p.FirstName, p.LastName, p.DateOfBirth, "
        "       TIMESTAMPDIFF(YEAR, p.DateOfBirth, CURDATE()) AS Age, p.Gender, "
        "       p.RetiredFormat1, p.RetiredFormat2, p.RetiredFormat3, p.ICC_Code "
        "FROM Player p WHERE p.ICC_Code = %s ORDER BY p.LastName, p.FirstName", (code,))


# ---------------------------- P: projection -------------------------
def team_rankings(fmt, gender, on_date=None):
    """P1 Team rankings table (latest snapshot) and H2 Team table on a past date
    (latest snapshot on or before on_date). Name, matches, points, rating, position."""
    return query_all(
        "SELECT v.ICC_Code, v.TeamName, v.Matches, v.Points, v.Rating, v.RankPos, v.EffectiveDate "
        "FROM v_team_rating v "
        "WHERE v.Format = %s AND v.Gender = %s "
        "  AND v.EffectiveDate = (SELECT MAX(tr.EffectiveDate) FROM TeamRating tr "
        "                         WHERE tr.Format = %s AND tr.Gender = %s "
        "                           AND tr.EffectiveDate <= COALESCE(%s, CURDATE())) "
        "ORDER BY v.RankPos, v.TeamName",
        (fmt, gender, fmt, gender, on_date))


def squad_summary(code):
    """P2 Squad summary: first name, last name, date of birth only."""
    return query_all(
        "SELECT FirstName, LastName, DateOfBirth FROM Player "
        "WHERE ICC_Code = %s ORDER BY LastName, FirstName", (code,))


def venues_in_country(country):
    """P3 Venue finder: name and city of the venues in a country."""
    return query_all("SELECT VenueName, City FROM Venue WHERE Country = %s ORDER BY City, VenueName",
                     (country,))


# ---------------------------- A: aggregates -------------------------
def peak_batting_points():
    """A1 Peak ratings: the maximum batting points ever recorded in each format."""
    return query_all(
        "SELECT pr.Format, pr.BattingPoints AS PeakPoints, "
        "       CONCAT(p.FirstName, ' ', p.LastName) AS Player, pr.SnapshotDate "
        "FROM PlayerRating pr JOIN Player p ON p.PlayerID = pr.PlayerID "
        "WHERE pr.BattingPoints = (SELECT MAX(x.BattingPoints) FROM PlayerRating x WHERE x.Format = pr.Format) "
        "ORDER BY pr.Format")


def league_average(fmt="Test", gender="Men"):
    """A2 League average: average team rating in the latest snapshot of a table
    (Phase 1 default: men's Test)."""
    return query_one(
        "SELECT Format, Gender, MAX(EffectiveDate) AS EffectiveDate, "
        "       ROUND(AVG(Rating), 1) AS AverageRating, COUNT(*) AS Teams "
        "FROM v_latest_team_rating WHERE Format = %s AND Gender = %s "
        "GROUP BY Format, Gender", (fmt, gender))


def squad_profile():
    """A4 Squad profile: per team, player count and youngest / oldest age."""
    return query_all(
        "SELECT t.ICC_Code, t.TeamName, COUNT(p.PlayerID) AS Players, "
        "       TIMESTAMPDIFF(YEAR, MAX(p.DateOfBirth), CURDATE()) AS YoungestAge, "
        "       TIMESTAMPDIFF(YEAR, MIN(p.DateOfBirth), CURDATE()) AS OldestAge "
        "FROM Team t LEFT JOIN Player p ON p.ICC_Code = t.ICC_Code "
        "GROUP BY t.ICC_Code, t.TeamName ORDER BY Players DESC, t.TeamName")


# ------------------------ A3 / Q2: series list ----------------------
def list_series(q=None, fmt=None, gender=None):
    """Q2 Find an event (partial name match, case-insensitive) and A3 Series size
    (match count per series). All filters optional."""
    pattern = like_pattern(q)
    return query_all(
        "SELECT s.SeriesID, s.SeriesName, s.SeriesType, s.Gender, s.Format, s.StartDate, s.EndDate, "
        "       e.SeriesName AS MainEventName, COUNT(m.MatchID) AS MatchCount "
        "FROM Series s "
        "LEFT JOIN Series e ON e.SeriesID = s.MainEventID "
        "LEFT JOIN CricketMatch m ON m.SeriesID = s.SeriesID "
        "WHERE (%s IS NULL OR LOWER(s.SeriesName) LIKE LOWER(%s)) "
        "  AND (%s IS NULL OR s.Format = %s) AND (%s IS NULL OR s.Gender = %s) "
        "GROUP BY s.SeriesID, s.SeriesName, s.SeriesType, s.Gender, s.Format, s.StartDate, s.EndDate, e.SeriesName "
        "ORDER BY s.StartDate DESC",
        (pattern, pattern, fmt, fmt, gender, gender))


def get_series(series_id):
    return query_one(
        "SELECT s.SeriesID, s.SeriesName, s.SeriesType, s.Gender, s.Format, s.StartDate, s.EndDate, "
        "       s.MainEventID, e.SeriesName AS MainEventName, "
        "       (SELECT COUNT(*) FROM CricketMatch m WHERE m.SeriesID = s.SeriesID) AS MatchCount "
        "FROM Series s LEFT JOIN Series e ON e.SeriesID = s.MainEventID WHERE s.SeriesID = %s",
        (series_id,))


def series_qualifiers(series_id):
    """Qualifier series that feed a main event (QUALIFIES_FOR)."""
    return query_all(
        "SELECT SeriesID, SeriesName, StartDate, EndDate FROM Series "
        "WHERE MainEventID = %s ORDER BY StartDate", (series_id,))


# ---------------------------- Q: searches ---------------------------
def search_players(q):
    """Q1 Find a player: partial match on first or last name, ignoring case."""
    pattern = like_pattern(q)
    if pattern is None:
        return []
    return query_all(
        "SELECT p.PlayerID, p.FirstName, p.LastName, p.Gender, t.TeamName, p.ICC_Code "
        "FROM Player p JOIN Team t ON t.ICC_Code = p.ICC_Code "
        "WHERE LOWER(p.FirstName) LIKE LOWER(%s) OR LOWER(p.LastName) LIKE LOWER(%s) "
        "ORDER BY p.LastName, p.FirstName", (pattern, pattern))


def search_venues(q):
    """Q3 Find a venue: partial match on city (all venues if empty), with derived MatchesHosted."""
    pattern = like_pattern(q)
    return query_all(
        "SELECT v.VenueID, v.VenueName, v.City, v.Country, COUNT(m.MatchID) AS MatchesHosted "
        "FROM Venue v LEFT JOIN CricketMatch m ON m.VenueID = v.VenueID "
        "WHERE (%s IS NULL OR LOWER(v.City) LIKE LOWER(%s)) "
        "GROUP BY v.VenueID, v.VenueName, v.City, v.Country ORDER BY v.Country, v.City, v.VenueName",
        (pattern, pattern))


# ---------------------------- H: history ----------------------------
def team_rating_history(code, fmt, gender):
    """H1 Team rating history: every saved snapshot, oldest first."""
    return query_all(
        "SELECT EffectiveDate, Matches, Points, Rating, RankPos FROM v_team_rating "
        "WHERE ICC_Code = %s AND Format = %s AND Gender = %s ORDER BY EffectiveDate",
        (code, fmt, gender))


def player_rating_history(player_id, fmt):
    """H3 Player rating history: every saved snapshot, oldest first."""
    return query_all(
        "SELECT SnapshotDate, BattingPoints, BowlingPoints, AllRounderIndex, "
        "       BattingRank, BowlingRank, AllRounderRank FROM v_player_rating "
        "WHERE PlayerID = %s AND Format = %s ORDER BY SnapshotDate", (player_id, fmt))


def player_table(fmt, gender, list_type="batting", on_date=None):
    """H4 Player table on a past date (and the current player rankings when on_date
    is None). list_type: batting, bowling or allrounder. Only the top 100 are published.
    In the current table, players retired from the format are left out."""
    points_col, rank_col = PLAYER_LISTS[list_type]          # whitelist lookup
    sql = (
        "SELECT v.PlayerID, v.FirstName, v.LastName, v.TeamName, v.SnapshotDate, "
        "       v.BattingPoints, v.BowlingPoints, v.AllRounderIndex, "
        "       v." + points_col + " AS Points, v." + rank_col + " AS RankPos "
        "FROM v_player_rating v "
        "WHERE v.Format = %s AND v.Gender = %s "
        "  AND v.SnapshotDate = (SELECT MAX(pr.SnapshotDate) FROM PlayerRating pr "
        "                        JOIN Player p ON p.PlayerID = pr.PlayerID "
        "                        WHERE pr.Format = %s AND p.Gender = %s "
        "                          AND pr.SnapshotDate <= COALESCE(%s, CURDATE())) "
        "  AND v." + points_col + " IS NOT NULL "
        "  AND (%s IS NOT NULL OR fn_player_retired(v.PlayerID, v.Format) = 0) "
        "  AND v." + rank_col + " <= 100 "
        "ORDER BY v." + rank_col + ", v.LastName")
    return query_all(sql, (fmt, gender, fmt, gender, on_date, on_date))

 
def position_changes(code, fmt, gender):
    """H5 Position changes: only the snapshot dates on which the team's position
    differed from the previous snapshot."""
    return query_all(
        "SELECT x.EffectiveDate, x.PrevPos, x.RankPos, x.Rating "
        "FROM (SELECT EffectiveDate, RankPos, Rating, "
        "             LAG(RankPos) OVER (ORDER BY EffectiveDate) AS PrevPos "
        "      FROM v_team_rating WHERE ICC_Code = %s AND Format = %s AND Gender = %s) x "
        "WHERE x.PrevPos IS NOT NULL AND x.PrevPos <> x.RankPos ORDER BY x.EffectiveDate",
        (code, fmt, gender))


def rating_change(fmt, gender, date1, date2):
    """H6 Rating change between two dates: each team's rating at both dates and the
    difference, largest rise first (snapshot = latest on or before each date)."""
    return query_all(
        "SELECT a.TeamName, a.EffectiveDate AS StartSnapshot, a.Rating AS RatingStart, "
        "       b.EffectiveDate AS EndSnapshot, b.Rating AS RatingEnd, b.Rating - a.Rating AS Difference "
        "FROM v_team_rating a "
        "JOIN v_team_rating b ON b.ICC_Code = a.ICC_Code AND b.Format = a.Format AND b.Gender = a.Gender "
        "WHERE a.Format = %s AND a.Gender = %s "
        "  AND a.EffectiveDate = (SELECT MAX(x.EffectiveDate) FROM TeamRating x "
        "                         WHERE x.Format = %s AND x.Gender = %s AND x.EffectiveDate <= %s) "
        "  AND b.EffectiveDate = (SELECT MAX(y.EffectiveDate) FROM TeamRating y "
        "                         WHERE y.Format = %s AND y.Gender = %s AND y.EffectiveDate <= %s) "
        "ORDER BY Difference DESC, a.TeamName",
        (fmt, gender, fmt, gender, date1, fmt, gender, date2))


# ---------------------------- R: reports ----------------------------
def top_ten_batters():
    """R1 Top ten per format: for each format and gender, the ten players with the
    highest batting points in the latest snapshot, with their team."""
    return query_all(
        "SELECT Format, Gender, BattingRank, CONCAT(FirstName, ' ', LastName) AS Player, "
        "       TeamName, BattingPoints, SnapshotDate "
        "FROM v_latest_player_rating "
        "WHERE BattingPoints IS NOT NULL AND BattingRank <= 10 "
        "ORDER BY Format, Gender, BattingRank, LastName")


def results_vs_rating(fmt, start_date, end_date):
    """R2 Results against rating: each team's wins, losses, ties, draws and no
    results in a date range and format, beside its latest rating."""
    return query_all(
        "SELECT t.TeamName, s.Gender, COUNT(*) AS Matches, "
        "       SUM(c.Outcome = 'Win') AS Wins, SUM(c.Outcome = 'Loss') AS Losses, "
        "       SUM(c.Outcome = 'Tie') AS Ties, SUM(c.Outcome = 'Draw') AS Draws, "
        "       SUM(c.Outcome = 'NoResult') AS NoResults, r.Rating AS LatestRating, r.RankPos AS LatestPosition "
        "FROM Contests c "
        "JOIN CricketMatch m ON m.MatchID = c.MatchID "
        "JOIN Series s ON s.SeriesID = m.SeriesID "
        "JOIN Team t ON t.ICC_Code = c.ICC_Code "
        "LEFT JOIN v_latest_team_rating r ON r.ICC_Code = t.ICC_Code AND r.Format = s.Format AND r.Gender = s.Gender "
        "WHERE s.Format = %s AND m.StartDate >= %s AND m.EndDate <= %s "
        "GROUP BY t.ICC_Code, t.TeamName, s.Gender, r.Rating, r.RankPos "
        "ORDER BY Wins DESC, t.TeamName",
        (fmt, start_date, end_date))


def rating_movement(fmt, gender):
    """R3 Rating movement: change in rating between the latest snapshot and the one
    nearest a year earlier, with the number of matches played in between."""
    return query_all(
        "WITH d AS (SELECT MAX(EffectiveDate) AS latest FROM TeamRating WHERE Format = %s AND Gender = %s), "
        "p AS (SELECT x.EffectiveDate AS prev_date "
        "      FROM (SELECT DISTINCT EffectiveDate FROM TeamRating WHERE Format = %s AND Gender = %s) x "
        "      CROSS JOIN d WHERE x.EffectiveDate < d.latest "
        "      ORDER BY ABS(DATEDIFF(x.EffectiveDate, DATE_SUB(d.latest, INTERVAL 1 YEAR))) LIMIT 1) "
        "SELECT b.TeamName, p.prev_date AS OldSnapshot, a.Rating AS OldRating, "
        "       d.latest AS NewSnapshot, b.Rating AS NewRating, b.Rating - a.Rating AS RatingChange, "
        "       (SELECT COUNT(*) FROM Contests c "
        "          JOIN CricketMatch m ON m.MatchID = c.MatchID "
        "          JOIN Series s ON s.SeriesID = m.SeriesID "
        "         WHERE c.ICC_Code = b.ICC_Code AND s.Format = b.Format AND s.Gender = b.Gender "
        "           AND m.EndDate > p.prev_date AND m.EndDate <= d.latest) AS MatchesBetween "
        "FROM d CROSS JOIN p "
        "JOIN v_team_rating b ON b.EffectiveDate = d.latest AND b.Format = %s AND b.Gender = %s "
        "JOIN v_team_rating a ON a.ICC_Code = b.ICC_Code AND a.Format = b.Format "
        "                    AND a.Gender = b.Gender AND a.EffectiveDate = p.prev_date "
        "ORDER BY RatingChange DESC, b.TeamName",
        (fmt, gender, fmt, gender, fmt, gender))


def world_class_allrounders(threshold=300):
    """R4 World-class all-rounders: all-rounder index above 300 in the latest snapshot."""
    return query_all(
        "SELECT CONCAT(FirstName, ' ', LastName) AS Player, Format, Gender, TeamName, "
        "       BattingPoints, BowlingPoints, AllRounderIndex, SnapshotDate "
        "FROM v_latest_player_rating WHERE AllRounderIndex > %s "
        "ORDER BY AllRounderIndex DESC", (threshold,))


def deep_benches():
    """R5 Deep benches: teams with more players on the latest published batting lists
    than the average number per team."""
    return query_all(
        "WITH cnt AS (SELECT t.ICC_Code, t.TeamName, COUNT(DISTINCT l.PlayerID) AS BattersListed "
        "             FROM Team t LEFT JOIN v_latest_player_rating l "
        "                    ON l.ICC_Code = t.ICC_Code AND l.BattingPoints IS NOT NULL "
        "             GROUP BY t.ICC_Code, t.TeamName) "
        "SELECT TeamName, BattersListed, (SELECT ROUND(AVG(BattersListed), 2) FROM cnt) AS AveragePerTeam "
        "FROM cnt WHERE BattersListed > (SELECT AVG(BattersListed) FROM cnt) "
        "ORDER BY BattersListed DESC, TeamName")


def event_pipeline():
    """R6 Event pipeline: for each ICC event, its qualifier series, how many matches
    they contained and which teams played in them."""
    return query_all(
        "SELECT e.SeriesName AS Event, q.SeriesName AS Qualifier, "
        "       COUNT(DISTINCT m.MatchID) AS QualifierMatches, "
        "       GROUP_CONCAT(DISTINCT t.TeamName ORDER BY t.TeamName SEPARATOR ', ') AS Teams "
        "FROM Series e "
        "JOIN Series q ON q.MainEventID = e.SeriesID "
        "LEFT JOIN CricketMatch m ON m.SeriesID = q.SeriesID "
        "LEFT JOIN Contests c ON c.MatchID = m.MatchID "
        "LEFT JOIN Team t ON t.ICC_Code = c.ICC_Code "
        "WHERE e.SeriesType = 'ICC Event' "
        "GROUP BY e.SeriesID, e.SeriesName, e.StartDate, q.SeriesID, q.SeriesName "
        "ORDER BY e.StartDate, q.StartDate")


def changed_allegiance():
    """R7 Changed allegiance: players who have appeared for a team other than the one
    they now represent."""
    return query_all(
        "SELECT p.PlayerID, CONCAT(p.FirstName, ' ', p.LastName) AS Player, "
        "       cur.TeamName AS CurrentTeam, past.TeamName AS PlayedFor, COUNT(*) AS Appearances "
        "FROM Player p "
        "JOIN PlaysIn pi ON pi.PlayerID = p.PlayerID "
        "JOIN Team cur  ON cur.ICC_Code  = p.ICC_Code "
        "JOIN Team past ON past.ICC_Code = pi.ICC_Code "
        "WHERE pi.ICC_Code <> p.ICC_Code "
        "GROUP BY p.PlayerID, p.FirstName, p.LastName, cur.TeamName, past.TeamName "
        "ORDER BY Player")


# ------------------------ detail pages -------------------------------
def get_player(player_id):
    return query_one(
        "SELECT p.PlayerID, p.FirstName, p.LastName, p.DateOfBirth, "
        "       TIMESTAMPDIFF(YEAR, p.DateOfBirth, CURDATE()) AS Age, p.Gender, "
        "       p.RetiredFormat1, p.RetiredFormat2, p.RetiredFormat3, p.ICC_Code, t.TeamName "
        "FROM Player p JOIN Team t ON t.ICC_Code = p.ICC_Code WHERE p.PlayerID = %s", (player_id,))


def player_appearances(player_id):
    """Matches a player appeared in, with the team he/she appeared for."""
    return query_all(
        "SELECT m.MatchID, m.StartDate, s.SeriesName, s.Format, v.VenueName, v.City, "
        "       t.TeamName AS AppearedFor, pi.IsCaptain "
        "FROM PlaysIn pi "
        "JOIN CricketMatch m ON m.MatchID = pi.MatchID "
        "JOIN Series s ON s.SeriesID = m.SeriesID "
        "JOIN Venue v ON v.VenueID = m.VenueID "
        "JOIN Team t ON t.ICC_Code = pi.ICC_Code "
        "WHERE pi.PlayerID = %s ORDER BY m.StartDate DESC", (player_id,))


def get_match(match_id):
    return query_one(
        "SELECT m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, m.VenueID, m.SeriesID, "
        "       s.SeriesName, s.Format, s.Gender, v.VenueName, v.City, v.Country, "
        "       tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied, "
        "       DATEDIFF(m.EndDate, m.StartDate) + 1 AS DurationDays "
        "FROM CricketMatch m "
        "JOIN Series s ON s.SeriesID = m.SeriesID "
        "JOIN Venue v ON v.VenueID = m.VenueID "
        "LEFT JOIN TestMatch tm ON tm.MatchID = m.MatchID "
        "LEFT JOIN LimitedOversMatch lom ON lom.MatchID = m.MatchID "
        "WHERE m.MatchID = %s", (match_id,))


def match_teams(match_id):
    return query_all(
        "SELECT c.ICC_Code, t.TeamName, c.Outcome FROM Contests c "
        "JOIN Team t ON t.ICC_Code = c.ICC_Code WHERE c.MatchID = %s ORDER BY t.TeamName", (match_id,))


def match_lineup(match_id):
    """Recorded playing squads (optional per Phase 1)."""
    return query_all(
        "SELECT t.TeamName, p.PlayerID, p.FirstName, p.LastName, pi.IsCaptain "
        "FROM PlaysIn pi JOIN Player p ON p.PlayerID = pi.PlayerID "
        "JOIN Team t ON t.ICC_Code = pi.ICC_Code "
        "WHERE pi.MatchID = %s ORDER BY t.TeamName, pi.IsCaptain DESC, p.LastName", (match_id,))


def list_later_snapshots(match_id):
    """U2 helper: every snapshot of the two teams (same format and gender) dated on or
    after the match end date; revised Points must be supplied for each before a result
    can be corrected."""
    return query_all(
        "SELECT tr.ICC_Code, t.TeamName, tr.EffectiveDate, tr.Matches, tr.Points "
        "FROM CricketMatch m "
        "JOIN Series s ON s.SeriesID = m.SeriesID "
        "JOIN Contests c ON c.MatchID = m.MatchID "
        "JOIN TeamRating tr ON tr.ICC_Code = c.ICC_Code AND tr.Format = s.Format "
        "                  AND tr.Gender = s.Gender AND tr.EffectiveDate >= m.EndDate "
        "JOIN Team t ON t.ICC_Code = tr.ICC_Code "
        "WHERE m.MatchID = %s ORDER BY tr.EffectiveDate, t.TeamName", (match_id,))


def latest_snapshot_date(fmt, gender):
    row = query_one("SELECT MAX(EffectiveDate) AS d FROM TeamRating WHERE Format = %s AND Gender = %s",
                    (fmt, gender))
    return row["d"] if row else None


def list_matches(fmt=None, series_id=None, team_code=None, q=None):
    """Search and filter matches with series info, venue, teams and outcome."""
    pattern = like_pattern(q)
    return query_all(
        "SELECT m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, "
        "       s.SeriesID, s.SeriesName, s.Format, s.Gender, "
        "       v.VenueName, v.City, v.Country, tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied, "
        "       GROUP_CONCAT(t.TeamName ORDER BY t.TeamName SEPARATOR ' vs ') AS Teams, "
        "       MAX(CASE WHEN c.Outcome = 'Win' THEN t.TeamName END) AS Winner, "
        "       MAX(CASE WHEN c.Outcome IN ('Tie','Draw','NoResult') THEN c.Outcome END) AS OtherResult "
        "FROM CricketMatch m "
        "JOIN Series s ON s.SeriesID = m.SeriesID "
        "JOIN Venue v ON v.VenueID = m.VenueID "
        "LEFT JOIN TestMatch tm ON tm.MatchID = m.MatchID "
        "LEFT JOIN LimitedOversMatch lom ON lom.MatchID = m.MatchID "
        "LEFT JOIN Contests c ON c.MatchID = m.MatchID "
        "LEFT JOIN Team t ON t.ICC_Code = c.ICC_Code "
        "WHERE (%s IS NULL OR s.Format = %s) "
        "  AND (%s IS NULL OR m.SeriesID = %s) "
        "  AND (%s IS NULL OR EXISTS (SELECT 1 FROM Contests c2 WHERE c2.MatchID = m.MatchID AND c2.ICC_Code = %s)) "
        "  AND (%s IS NULL OR LOWER(s.SeriesName) LIKE LOWER(%s) OR LOWER(v.City) LIKE LOWER(%s)) "
        "GROUP BY m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, "
        "         s.SeriesID, s.SeriesName, s.Format, s.Gender, "
        "         v.VenueName, v.City, v.Country, tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied "
        "ORDER BY m.StartDate DESC, m.MatchID DESC",
        (fmt, fmt, series_id, series_id, team_code, team_code, pattern, pattern, pattern))


def get_counts():
    """Summary counts for the dashboard overview."""
    row = query_one(
        "SELECT "
        "(SELECT COUNT(*) FROM Team) AS team_count, "
        "(SELECT COUNT(*) FROM CricketMatch) AS match_count, "
        "(SELECT COUNT(*) FROM Series) AS series_count, "
        "(SELECT COUNT(*) FROM Venue) AS venue_count, "
        "(SELECT COUNT(*) FROM Player) AS player_count"
    )
    return row or {"team_count": 0, "match_count": 0, "series_count": 0, "venue_count": 0, "player_count": 0}


def get_featured_rankings():
    """Top-ranked teams and players for the homepage showcase."""
    top_teams = query_all(
        "SELECT Format, Gender, TeamName, Rating, Matches, Points "
        "FROM v_latest_team_rating WHERE RankPos = 1 ORDER BY Gender, Format"
    )
    top_players = query_all(
        "SELECT Format, Gender, CONCAT(FirstName, ' ', LastName) AS Player, TeamName, BattingPoints, BowlingPoints, BattingRank, BowlingRank "
        "FROM v_latest_player_rating "
        "WHERE BattingRank = 1 OR BowlingRank = 1 "
        "ORDER BY Gender, Format"
    )
    return {"teams": top_teams, "players": top_players}


def list_matches(fmt=None, series_id=None, team_code=None, q=None):
    """Search and filter matches with series info, venue, teams and outcome."""
    pattern = like_pattern(q)
    return query_all(
        "SELECT m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, "
        "       s.SeriesID, s.SeriesName, s.Format, s.Gender, "
        "       v.VenueName, v.City, v.Country, tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied, "
        "       GROUP_CONCAT(t.TeamName ORDER BY t.TeamName SEPARATOR ' vs ') AS Teams, "
        "       MAX(CASE WHEN c.Outcome = 'Win' THEN t.TeamName END) AS Winner, "
        "       MAX(CASE WHEN c.Outcome IN ('Tie','Draw','NoResult') THEN c.Outcome END) AS OtherResult "
        "FROM CricketMatch m "
        "JOIN Series s ON s.SeriesID = m.SeriesID "
        "JOIN Venue v ON v.VenueID = m.VenueID "
        "LEFT JOIN TestMatch tm ON tm.MatchID = m.MatchID "
        "LEFT JOIN LimitedOversMatch lom ON lom.MatchID = m.MatchID "
        "LEFT JOIN Contests c ON c.MatchID = m.MatchID "
        "LEFT JOIN Team t ON t.ICC_Code = c.ICC_Code "
        "WHERE (%s IS NULL OR s.Format = %s) "
        "  AND (%s IS NULL OR m.SeriesID = %s) "
        "  AND (%s IS NULL OR EXISTS (SELECT 1 FROM Contests c2 WHERE c2.MatchID = m.MatchID AND c2.ICC_Code = %s)) "
        "  AND (%s IS NULL OR LOWER(s.SeriesName) LIKE LOWER(%s) OR LOWER(v.City) LIKE LOWER(%s)) "
        "GROUP BY m.MatchID, m.StartDate, m.EndDate, m.MarginValue, m.MarginType, "
        "         s.SeriesID, s.SeriesName, s.Format, s.Gender, "
        "         v.VenueName, v.City, v.Country, tm.ScheduledDays, lom.OversPerSide, lom.DLSApplied "
        "ORDER BY m.StartDate DESC, m.MatchID DESC",
        (fmt, fmt, series_id, series_id, team_code, team_code, pattern, pattern, pattern))


def get_counts():
    """Summary counts for the dashboard overview."""
    row = query_one(
        "SELECT "
        "(SELECT COUNT(*) FROM Team) AS team_count, "
        "(SELECT COUNT(*) FROM CricketMatch) AS match_count, "
        "(SELECT COUNT(*) FROM Series) AS series_count, "
        "(SELECT COUNT(*) FROM Venue) AS venue_count, "
        "(SELECT COUNT(*) FROM Player) AS player_count"
    )
    return row or {"team_count": 0, "match_count": 0, "series_count": 0, "venue_count": 0, "player_count": 0}


def get_featured_rankings():
    """Top-ranked teams and players for the homepage showcase."""
    top_teams = query_all(
        "SELECT Format, Gender, TeamName, Rating, Matches, Points "
        "FROM v_latest_team_rating WHERE RankPos = 1 ORDER BY Gender, Format"
    )
    top_players = query_all(
        "SELECT Format, Gender, CONCAT(FirstName, ' ', LastName) AS Player, TeamName, BattingPoints, BowlingPoints, BattingRank, BowlingRank "
        "FROM v_latest_player_rating "
        "WHERE BattingRank = 1 OR BowlingRank = 1 "
        "ORDER BY Gender, Format"
    )
    return {"teams": top_teams, "players": top_players}
