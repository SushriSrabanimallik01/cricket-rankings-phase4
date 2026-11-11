"""operations.py - every WRITE operation (create / update / delete), raw SQL.

Each function runs in ONE transaction (database.transaction): either everything
succeeds and is committed, or everything is rolled back and an OperationError
with a readable message is raised. The triggers and constraints created in
schema.sql do the integrity checks (C1-C16); this module adds the checks that
need several statements or a friendly message.
"""
from database import OperationError, transaction

FORMATS = ("Test", "ODI", "T20I")
GENDERS = ("Men", "Women")
RESULTS = ("Win", "Tie", "Draw", "NoResult")
MARGIN_TYPES = ("Runs", "Wickets", "InningsAndRuns")

# Fixed SQL per retirement slot (column names are never built from user input).
_RETIRE_SQL = {
    1: "UPDATE Player SET RetiredFormat1 = %s WHERE PlayerID = %s",
    2: "UPDATE Player SET RetiredFormat2 = %s WHERE PlayerID = %s",
    3: "UPDATE Player SET RetiredFormat3 = %s WHERE PlayerID = %s",
}


def _none_if_blank(value):
    if value is None:
        return None
    value = str(value).strip()
    return value or None


# ---------------------------------------------------------------------
# I1  Add a match (match row + subclass row + exactly two CONTESTS rows)
# ---------------------------------------------------------------------
def add_match(series_id, venue_id, start_date, end_date, team1, team2,
              scheduled_days=None, dls_applied=False):
    """Insert CricketMatch, TestMatch/LimitedOversMatch and the two Contests rows.
    The subclass and OversPerSide follow the series format (Test: ScheduledDays 4 or 5;
    ODI: 50 overs; T20I: 20 overs). Returns the new MatchID."""
    if not team1 or not team2 or team1 == team2:
        raise OperationError("C6: a match needs two different teams.")
    with transaction() as cur:
        cur.execute("SELECT Format FROM Series WHERE SeriesID = %s", (series_id,))
        series = cur.fetchone()
        if series is None:
            raise OperationError("The chosen series does not exist.")
        fmt = series["Format"]

        cur.execute(
            "INSERT INTO CricketMatch (StartDate, EndDate, VenueID, SeriesID) VALUES (%s, %s, %s, %s)",
            (start_date, end_date, venue_id, series_id))
        match_id = cur.lastrowid

        if fmt == "Test":
            if str(scheduled_days) not in ("4", "5"):
                raise OperationError("C4: a Test match is scheduled for 4 or 5 days.")
            cur.execute("INSERT INTO TestMatch (MatchID, ScheduledDays) VALUES (%s, %s)",
                        (match_id, int(scheduled_days)))
        else:
            overs = 50 if fmt == "ODI" else 20
            cur.execute("INSERT INTO LimitedOversMatch (MatchID, OversPerSide, DLSApplied) VALUES (%s, %s, %s)",
                        (match_id, overs, 1 if dls_applied else 0))

        cur.execute("INSERT INTO Contests (MatchID, ICC_Code) VALUES (%s, %s)", (match_id, team1))
        cur.execute("INSERT INTO Contests (MatchID, ICC_Code) VALUES (%s, %s)", (match_id, team2))

        cur.execute("SELECT COUNT(*) AS n FROM Contests WHERE MatchID = %s", (match_id,))
        if cur.fetchone()["n"] != 2:                       # C6: exactly two teams
            raise OperationError("C6: a match must have exactly two teams.")
        return match_id


# ---------------------------------------------------------------------
# I2  Load a weekly player snapshot (all rows or none)
# ---------------------------------------------------------------------
def load_player_snapshot(fmt, snapshot_date, rows):
    """rows: list of (player_id, batting_points or None, bowling_points or None).
    The triggers check weekday (C11), no women's Tests (C12), retirement and the
    qualifying window (C13) and the 100-player list limit (C14)."""
    if fmt not in FORMATS:
        raise OperationError("Choose a valid format.")
    if not rows:
        raise OperationError("Enter at least one player row.")
    with transaction() as cur:
        for player_id, batting, bowling in rows:
            cur.execute(
                "INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) "
                "VALUES (%s, %s, %s, %s, %s)",
                (player_id, fmt, snapshot_date, batting, bowling))
    return len(rows)


# ---------------------------------------------------------------------
# I3  Register a player
# ---------------------------------------------------------------------
def register_player(first_name, last_name, date_of_birth, gender, team_code):
    """Insert a PLAYER with its REPRESENTS link (retired formats start empty)."""
    first_name, last_name = _none_if_blank(first_name), _none_if_blank(last_name)
    if not first_name or not last_name:
        raise OperationError("Both a first name and a last name are required.")
    if gender not in GENDERS:
        raise OperationError("Gender must be Men or Women.")
    with transaction() as cur:
        cur.execute(
            "INSERT INTO Player (FirstName, LastName, DateOfBirth, Gender, ICC_Code) "
            "VALUES (%s, %s, %s, %s, %s)",
            (first_name, last_name, date_of_birth, gender, team_code))
        return cur.lastrowid


# ---------------------------------------------------------------------
# U1  Record a match result (and optionally the new team rating snapshot)
# ---------------------------------------------------------------------
def _apply_result(cur, match_id, result, winner_code, margin_value, margin_type):
    cur.execute("SELECT ICC_Code FROM Contests WHERE MatchID = %s ORDER BY ICC_Code", (match_id,))
    teams = [r["ICC_Code"] for r in cur.fetchall()]
    if len(teams) != 2:
        raise OperationError("This match does not have exactly two teams.")
    if result not in RESULTS:
        raise OperationError("Choose a result: Win, Tie, Draw or NoResult.")
    margin_value, margin_type = _none_if_blank(margin_value), _none_if_blank(margin_type)
    if result == "Win":
        if winner_code not in teams:
            raise OperationError("C7: the winner must be one of the two teams of the match.")
        if (margin_value is None) != (margin_type is None):
            raise OperationError("Give both a margin value and a margin type, or neither.")
        if margin_type is not None and margin_type not in MARGIN_TYPES:
            raise OperationError("Margin type must be Runs, Wickets or InningsAndRuns.")
    elif margin_value is not None or margin_type is not None:
        raise OperationError("C7: a margin is recorded only for a Win.")

    # clear the previous result first, so a correction never trips the complementary-outcome rule
    cur.execute("UPDATE Contests SET Outcome = NULL WHERE MatchID = %s", (match_id,))
    cur.execute("UPDATE CricketMatch SET MarginValue = NULL, MarginType = NULL WHERE MatchID = %s", (match_id,))

    if result == "Win":
        loser = teams[0] if teams[1] == winner_code else teams[1]
        cur.execute("UPDATE Contests SET Outcome = 'Win'  WHERE MatchID = %s AND ICC_Code = %s", (match_id, winner_code))
        cur.execute("UPDATE Contests SET Outcome = 'Loss' WHERE MatchID = %s AND ICC_Code = %s", (match_id, loser))
        if margin_value is not None:
            cur.execute("UPDATE CricketMatch SET MarginValue = %s, MarginType = %s WHERE MatchID = %s",
                        (int(margin_value), margin_type, match_id))
    else:
        cur.execute("UPDATE Contests SET Outcome = %s WHERE MatchID = %s", (result, match_id))
    return teams


def _add_table_snapshot(cur, fmt, gender, effective_date, points_added):
    """Publish a new full table: copy the latest table, adding one match and the
    given points to each team in points_added ({ICC_Code: points}); other teams are
    carried forward unchanged, as the ICC publishes the whole table each time."""
    cur.execute("SELECT MAX(EffectiveDate) AS d FROM TeamRating WHERE Format = %s AND Gender = %s", (fmt, gender))
    latest = cur.fetchone()["d"]
    if latest is None:
        raise OperationError("There is no earlier table for this format and gender to build on.")
    cur.execute("SELECT %s > %s AS ok", (effective_date, latest))
    if not cur.fetchone()["ok"]:
        raise OperationError("C11: the new snapshot must be dated after the latest one (%s)." % latest)
    codes = list(points_added.keys())
    placeholders = ", ".join(["%s"] * len(codes))
    cur.execute(
        "INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) "
        "SELECT tr.ICC_Code, tr.Format, tr.Gender, %s, tr.Matches, tr.Points FROM TeamRating tr "
        "WHERE tr.Format = %s AND tr.Gender = %s AND tr.EffectiveDate = %s "
        "  AND tr.ICC_Code NOT IN (" + placeholders + ")",
        [effective_date, fmt, gender, latest] + codes)
    for code, points in points_added.items():
        cur.execute(
            "INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) "
            "SELECT tr.ICC_Code, tr.Format, tr.Gender, %s, tr.Matches + 1, tr.Points + %s FROM TeamRating tr "
            "WHERE tr.ICC_Code = %s AND tr.Format = %s AND tr.Gender = %s AND tr.EffectiveDate = %s",
            (effective_date, int(points), code, fmt, gender, latest))
        if cur.rowcount != 1:
            raise OperationError("Team %s is not in the latest %s %s table." % (code, gender, fmt))


def record_result(match_id, result, winner_code=None, margin_value=None, margin_type=None,
                  points_added=None, effective_date=None):
    """Set each team's Outcome and the winning margin (C7). If points_added
    ({ICC_Code: points}) is given, a new rating snapshot is inserted in the same
    transaction: Matches +1 and Points +points for each of the two teams;
    Rating and Position then follow automatically (they are derived)."""
    with transaction() as cur:
        teams = _apply_result(cur, match_id, result, winner_code, margin_value, margin_type)
        if points_added:
            if set(points_added.keys()) != set(teams):
                raise OperationError("Give the new Points for both teams of the match.")
            cur.execute("SELECT s.Format, s.Gender, m.EndDate FROM CricketMatch m "
                        "JOIN Series s ON s.SeriesID = m.SeriesID WHERE m.MatchID = %s", (match_id,))
            info = cur.fetchone()
            _add_table_snapshot(cur, info["Format"], info["Gender"],
                                effective_date or info["EndDate"], points_added)


# ---------------------------------------------------------------------
# U2  Correct a recorded result after a ruling
# ---------------------------------------------------------------------
def correct_result(match_id, result, winner_code, margin_value, margin_type, revised_points):
    """revised_points: {(ICC_Code, 'YYYY-MM-DD'): new_points} for EVERY later snapshot of
    the two teams (see queries.list_later_snapshots). The correction is blocked until all
    are supplied; earlier snapshots are untouched."""
    with transaction() as cur:
        cur.execute(
            "SELECT tr.ICC_Code, tr.EffectiveDate FROM CricketMatch m "
            "JOIN Series s ON s.SeriesID = m.SeriesID "
            "JOIN Contests c ON c.MatchID = m.MatchID "
            "JOIN TeamRating tr ON tr.ICC_Code = c.ICC_Code AND tr.Format = s.Format "
            "                  AND tr.Gender = s.Gender AND tr.EffectiveDate >= m.EndDate "
            "WHERE m.MatchID = %s", (match_id,))
        later = [(r["ICC_Code"], str(r["EffectiveDate"])) for r in cur.fetchall()]
        missing = [k for k in later if k not in revised_points]
        if missing:
            raise OperationError("Blocked: supply revised Points for every later snapshot. Missing: "
                                 + ", ".join("%s on %s" % k for k in missing))
        _apply_result(cur, match_id, result, winner_code, margin_value, margin_type)
        for (code, date), points in revised_points.items():
            if (code, date) not in later:
                continue
            cur.execute(
                "UPDATE TeamRating tr JOIN CricketMatch m ON m.MatchID = %s "
                "JOIN Series s ON s.SeriesID = m.SeriesID "
                "SET tr.Points = %s "
                "WHERE tr.ICC_Code = %s AND tr.EffectiveDate = %s AND tr.Format = s.Format AND tr.Gender = s.Gender",
                (match_id, int(points), code, date))


# ---------------------------------------------------------------------
# U3  Record a retirement
# ---------------------------------------------------------------------
def record_retirement(player_id, fmt):
    """Add a format to the player's RetiredFormats (allowed only if the player has
    appeared in it; the trigger enforces that). Earlier snapshots stay as history."""
    if fmt not in FORMATS:
        raise OperationError("Choose a valid format.")
    with transaction() as cur:
        cur.execute("SELECT RetiredFormat1, RetiredFormat2, RetiredFormat3 FROM Player WHERE PlayerID = %s",
                    (player_id,))
        row = cur.fetchone()
        if row is None:
            raise OperationError("That player does not exist.")
        slots = [row["RetiredFormat1"], row["RetiredFormat2"], row["RetiredFormat3"]]
        if fmt in slots:
            raise OperationError("The player is already recorded as retired from %s." % fmt)
        slot = slots.index(None) + 1
        cur.execute(_RETIRE_SQL[slot], (fmt, player_id))


# ---------------------------------------------------------------------
# U4  Change a team's eligible formats
# ---------------------------------------------------------------------
def set_eligible_formats(team_code, formats):
    """Replace the team's EligibleFormats (1 to 3 of Test, ODI, T20I). New matches and
    snapshots in an ineligible format are then refused; existing rows stay as history."""
    formats = [f for f in dict.fromkeys(formats) if f]          # unique, order kept
    if not 1 <= len(formats) <= 3 or any(f not in FORMATS for f in formats):
        raise OperationError("Choose between one and three formats from Test, ODI and T20I.")
    padded = formats + [None] * (3 - len(formats))
    with transaction() as cur:
        cur.execute(
            "UPDATE Team SET EligibleFormat1 = %s, EligibleFormat2 = %s, EligibleFormat3 = %s "
            "WHERE ICC_Code = %s", (padded[0], padded[1], padded[2], team_code))
        cur.execute("SELECT COUNT(*) AS n FROM Team WHERE ICC_Code = %s", (team_code,))
        if cur.fetchone()["n"] != 1:
            raise OperationError("That team does not exist.")


# ---------------------------------------------------------------------
# U5  Move a player to another team
# ---------------------------------------------------------------------
def move_player(player_id, new_team_code):
    """Change the REPRESENTS link. Past PLAYS_IN rows keep the team the player appeared for."""
    with transaction() as cur:
        cur.execute("SELECT ICC_Code FROM Player WHERE PlayerID = %s", (player_id,))
        row = cur.fetchone()
        if row is None:
            raise OperationError("That player does not exist.")
        if row["ICC_Code"] == new_team_code:
            raise OperationError("The player already represents that team.")
        cur.execute("UPDATE Player SET ICC_Code = %s WHERE PlayerID = %s", (new_team_code, player_id))


# ---------------------------------------------------------------------
# D1  Delete a match entered in error (children cascade)
# ---------------------------------------------------------------------
def delete_match(match_id):
    """Its CONTESTS, PLAYS_IN and subclass rows are deleted with it (ON DELETE CASCADE)."""
    with transaction() as cur:
        cur.execute("DELETE FROM CricketMatch WHERE MatchID = %s", (match_id,))
        if cur.rowcount != 1:
            raise OperationError("That match does not exist.")


# ---------------------------------------------------------------------
# D2  Delete a duplicate player (refused while appearances exist)
# ---------------------------------------------------------------------
def move_appearances(from_player_id, to_player_id):
    """Move PLAYS_IN rows from a duplicate record to the surviving record."""
    if from_player_id == to_player_id:
        raise OperationError("Choose two different players.")
    with transaction() as cur:
        cur.execute("UPDATE PlaysIn SET PlayerID = %s WHERE PlayerID = %s", (to_player_id, from_player_id))
        return cur.rowcount


def delete_player(player_id):
    """Ratings are deleted with the player (cascade); refused if PLAYS_IN rows exist."""
    with transaction() as cur:
        cur.execute("DELETE FROM Player WHERE PlayerID = %s", (player_id,))
        if cur.rowcount != 1:
            raise OperationError("That player does not exist.")