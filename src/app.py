"""app.py - Main Flask application for ICC Cricket Rankings.

Routes coordinate between the HTML templates and the raw SQL queries in
queries.py and operations.py. All database interaction uses parameterised
queries through database.py.
"""
import os
import sys

# Ensure src directory is in sys.path
SRC_DIR = os.path.dirname(os.path.abspath(__file__))
if SRC_DIR not in sys.path:
    sys.path.insert(0, SRC_DIR)

from flask import (
    Flask,
    flash,
    redirect,
    render_template,
    request,
    url_for,
)

from database import OperationError
import operations as ops
import queries as qry

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "icc-cricket-rankings-phase4-key-2026")


# ---------------------------------------------------------------------
# Context processor: make constants & lists available to all templates
# ---------------------------------------------------------------------
@app.context_processor
def inject_globals():
    return {
        "FORMATS": qry.FORMATS,
        "GENDERS": qry.GENDERS,
        "RESULTS": ops.RESULTS,
        "MARGIN_TYPES": ops.MARGIN_TYPES,
        "PLAYER_LISTS": qry.PLAYER_LISTS,
    }


# ---------------------------------------------------------------------
# 1. Homepage / Dashboard
# ---------------------------------------------------------------------
@app.route("/")
def index():
    try:
        counts = qry.get_counts()
        featured = qry.get_featured_rankings()
        recent_matches = qry.list_matches()[:6]
        peak_batters = qry.peak_batting_points()
    except Exception as e:
        flash(f"Database connection error: {e}", "danger")
        counts = {"team_count": 0, "match_count": 0, "series_count": 0, "venue_count": 0, "player_count": 0}
        featured = {"teams": [], "players": []}
        recent_matches = []
        peak_batters = []

    return render_template(
        "index.html",
        counts=counts,
        featured=featured,
        recent_matches=recent_matches,
        peak_batters=peak_batters,
    )


# ---------------------------------------------------------------------
# 2. Rankings Hub (Teams, Players, History, Analysis)
# ---------------------------------------------------------------------
@app.route("/rankings")
def rankings():
    tab = request.args.get("tab", "teams")
    fmt = request.args.get("format", "Test")
    gender = request.args.get("gender", "Men")
    list_type = request.args.get("list_type", "batting")
    on_date = request.args.get("on_date", "").strip() or None
    selected_team = request.args.get("team", "IND")
    date1 = request.args.get("date1", "").strip() or None
    date2 = request.args.get("date2", "").strip() or None

    # Avoid invalid women's test combinations
    if gender == "Women" and fmt == "Test":
        fmt = "ODI"

    team_data = []
    player_data = []
    avg_rating = None
    team_history = []
    pos_changes = []
    rating_diffs = []
    movement_data = []
    top_ten = []
    allrounders = []
    benches = []

    all_teams = qry.all_teams()

    try:
        if tab == "teams":
            team_data = qry.team_rankings(fmt, gender, on_date)
            avg_rating = qry.league_average(fmt, gender)
        elif tab == "players":
            player_data = qry.player_table(fmt, gender, list_type, on_date)
        elif tab == "history":
            team_history = qry.team_rating_history(selected_team, fmt, gender)
            pos_changes = qry.position_changes(selected_team, fmt, gender)
            if date1 and date2:
                rating_diffs = qry.rating_change(fmt, gender, date1, date2)
            movement_data = qry.rating_movement(fmt, gender)
        elif tab == "analyst":
            top_ten = qry.top_ten_batters()
            allrounders = qry.world_class_allrounders(300)
            benches = qry.deep_benches()
    except Exception as e:
        flash(f"Error loading rankings: {e}", "danger")

    return render_template(
        "rankings.html",
        tab=tab,
        format=fmt,
        gender=gender,
        list_type=list_type,
        on_date=on_date,
        team_code=selected_team,
        date1=date1,
        date2=date2,
        team_data=team_data,
        player_data=player_data,
        avg_rating=avg_rating,
        team_history=team_history,
        pos_changes=pos_changes,
        rating_diffs=rating_diffs,
        movement_data=movement_data,
        top_ten=top_ten,
        allrounders=allrounders,
        benches=benches,
        all_teams=all_teams,
    )


# ---------------------------------------------------------------------
# 3. Teams Explorer
# ---------------------------------------------------------------------
@app.route("/teams")
def teams():
    fmt = request.args.get("format", "").strip() or None
    try:
        team_list = qry.list_teams(fmt)
        profiles = qry.squad_profile()
        profile_map = {p["ICC_Code"]: p for p in profiles}
    except Exception as e:
        flash(f"Error loading teams: {e}", "danger")
        team_list = []
        profile_map = {}

    return render_template("teams.html", teams=team_list, format_filter=fmt, profile_map=profile_map)


# ---------------------------------------------------------------------
# 4. Players Explorer & Search
# ---------------------------------------------------------------------
@app.route("/players")
def players():
    q = request.args.get("q", "").strip()
    team_code = request.args.get("team", "").strip() or None
    all_teams = qry.all_teams()
    players_list = []

    try:
        if q:
            players_list = qry.search_players(q)
        elif team_code:
            players_list = qry.squad(team_code)
        else:
            players_list = qry.all_players()
    except Exception as e:
        flash(f"Error searching players: {e}", "danger")

    return render_template(
        "players.html",
        players=players_list,
        search_query=q,
        selected_team=team_code,
        all_teams=all_teams,
    )


# ---------------------------------------------------------------------
# 5. Player Details
# ---------------------------------------------------------------------
@app.route("/players/<int:player_id>")
def player_details(player_id):
    try:
        player = qry.get_player(player_id)
        if not player:
            flash(f"Player with ID #{player_id} not found.", "warning")
            return redirect(url_for("players"))

        test_history = qry.player_rating_history(player_id, "Test")
        odi_history = qry.player_rating_history(player_id, "ODI")
        t20i_history = qry.player_rating_history(player_id, "T20I")
        appearances = qry.player_appearances(player_id)
        all_teams = qry.all_teams()
    except Exception as e:
        flash(f"Error loading player details: {e}", "danger")
        return redirect(url_for("players"))

    return render_template(
        "player_details.html",
        player=player,
        test_history=test_history,
        odi_history=odi_history,
        t20i_history=t20i_history,
        appearances=appearances,
        all_teams=all_teams,
    )


# ---------------------------------------------------------------------
# 6. Matches Explorer & Search
# ---------------------------------------------------------------------
@app.route("/matches")
def matches():
    fmt = request.args.get("format", "").strip() or None
    series_id = request.args.get("series_id", "").strip() or None
    team_code = request.args.get("team", "").strip() or None
    q = request.args.get("q", "").strip() or None

    all_series = qry.all_series()
    all_teams = qry.all_teams()

    try:
        match_list = qry.list_matches(fmt=fmt, series_id=series_id, team_code=team_code, q=q)
    except Exception as e:
        flash(f"Error loading matches: {e}", "danger")
        match_list = []

    return render_template(
        "matches.html",
        matches=match_list,
        format_filter=fmt,
        series_id=series_id,
        team_code=team_code,
        search_query=q or "",
        all_series=all_series,
        all_teams=all_teams,
    )


# ---------------------------------------------------------------------
# 7. Match Details
# ---------------------------------------------------------------------
@app.route("/matches/<int:match_id>")
def match_details(match_id):
    try:
        match = qry.get_match(match_id)
        if not match:
            flash(f"Match #{match_id} not found.", "warning")
            return redirect(url_for("matches"))

        teams = qry.match_teams(match_id)
        lineup = qry.match_lineup(match_id)
        later_snapshots = qry.list_later_snapshots(match_id)
    except Exception as e:
        flash(f"Error loading match #{match_id}: {e}", "danger")
        return redirect(url_for("matches"))

    return render_template(
        "match_details.html",
        match=match,
        teams=teams,
        lineup=lineup,
        later_snapshots=later_snapshots,
    )


# ---------------------------------------------------------------------
# 8. Series Explorer & Qualifier Pipeline
# ---------------------------------------------------------------------
@app.route("/series")
def series():
    q = request.args.get("q", "").strip() or None
    fmt = request.args.get("format", "").strip() or None
    gender = request.args.get("gender", "").strip() or None
    selected_id = request.args.get("id", "").strip() or None

    try:
        series_list = qry.list_series(q=q, fmt=fmt, gender=gender)
        pipeline = qry.event_pipeline()

        selected_series = None
        fixtures = []
        qualifiers = []
        if selected_id:
            selected_series = qry.get_series(selected_id)
            fixtures = qry.series_matches(selected_id)
            qualifiers = qry.series_qualifiers(selected_id)
    except Exception as e:
        flash(f"Error loading series: {e}", "danger")
        series_list = []
        pipeline = []
        selected_series = None
        fixtures = []
        qualifiers = []

    return render_template(
        "series.html",
        series_list=series_list,
        pipeline=pipeline,
        selected_series=selected_series,
        fixtures=fixtures,
        qualifiers=qualifiers,
        search_query=q or "",
        format_filter=fmt,
        gender_filter=gender,
    )


# ---------------------------------------------------------------------
# 9. Venues Finder
# ---------------------------------------------------------------------
@app.route("/venues")
def venues():
    country = request.args.get("country", "").strip() or None
    city_query = request.args.get("q", "").strip() or None

    all_countries = qry.list_countries()
    try:
        if country:
            venue_list = qry.venues_in_country(country)
        else:
            venue_list = qry.search_venues(city_query)
    except Exception as e:
        flash(f"Error loading venues: {e}", "danger")
        venue_list = []

    return render_template(
        "venues.html",
        venues=venue_list,
        selected_country=country,
        city_query=city_query or "",
        countries=all_countries,
    )


# ---------------------------------------------------------------------
# 10. Reports Hub (R2, R3, R5, R6, R7)
# ---------------------------------------------------------------------
@app.route("/reports")
def reports():
    fmt = request.args.get("format", "Test")
    start_date = request.args.get("start_date", "2025-01-01")
    end_date = request.args.get("end_date", "2026-12-31")

    try:
        results_rating = qry.results_vs_rating(fmt, start_date, end_date)
        allegiance = qry.changed_allegiance()
        allrounders = qry.world_class_allrounders(300)
        benches = qry.deep_benches()
    except Exception as e:
        flash(f"Error generating reports: {e}", "danger")
        results_rating = []
        allegiance = []
        allrounders = []
        benches = []

    return render_template(
        "reports.html",
        format=fmt,
        start_date=start_date,
        end_date=end_date,
        results_rating=results_rating,
        allegiance=allegiance,
        allrounders=allrounders,
        benches=benches,
    )


# ---------------------------------------------------------------------
# 11. Admin Portal & Operations (I1-I3, U1-U5, D1-D2)
# ---------------------------------------------------------------------
@app.route("/admin")
def admin():
    action = request.args.get("action", "match_add")
    all_teams = qry.all_teams()
    all_venues = qry.all_venues()
    all_series = qry.all_series()
    all_players = qry.all_players()
    all_matches = qry.list_matches()

    match_id = request.args.get("match_id")
    target_match = None
    later_snapshots = []
    if match_id:
        target_match = qry.get_match(match_id)
        if target_match:
            later_snapshots = qry.list_later_snapshots(match_id)

    return render_template(
        "admin.html",
        action=action,
        all_teams=all_teams,
        all_venues=all_venues,
        all_series=all_series,
        all_players=all_players,
        all_matches=all_matches,
        target_match=target_match,
        later_snapshots=later_snapshots,
    )


# I1: Add a Match
@app.route("/admin/match/add", methods=["POST"])
def admin_add_match():
    series_id = request.form.get("series_id")
    venue_id = request.form.get("venue_id")
    start_date = request.form.get("start_date")
    end_date = request.form.get("end_date")
    team1 = request.form.get("team1")
    team2 = request.form.get("team2")
    scheduled_days = request.form.get("scheduled_days")
    dls_applied = request.form.get("dls_applied") == "1"

    try:
        new_id = ops.add_match(
            series_id=series_id,
            venue_id=venue_id,
            start_date=start_date,
            end_date=end_date,
            team1=team1,
            team2=team2,
            scheduled_days=scheduled_days,
            dls_applied=dls_applied,
        )
        flash(f"Successfully scheduled Match #{new_id} ({team1} vs {team2}).", "success")
        return redirect(url_for("match_details", match_id=new_id))
    except (OperationError, Exception) as e:
        flash(f"Failed to add match: {e}", "danger")
        return redirect(url_for("admin", action="match_add"))


# I2: Load Player Snapshot
@app.route("/admin/snapshot/player", methods=["POST"])
def admin_load_player_snapshot():
    fmt = request.form.get("format")
    snapshot_date = request.form.get("snapshot_date")
    player_ids = request.form.getlist("player_id[]")
    batting_pts = request.form.getlist("batting[]")
    bowling_pts = request.form.getlist("bowling[]")

    rows = []
    for pid, bat, bowl in zip(player_ids, batting_pts, bowling_pts):
        pid = pid.strip()
        if not pid:
            continue
        bat_val = int(bat.strip()) if bat.strip() else None
        bowl_val = int(bowl.strip()) if bowl.strip() else None
        rows.append((int(pid), bat_val, bowl_val))

    try:
        count = ops.load_player_snapshot(fmt, snapshot_date, rows)
        flash(f"Successfully loaded {count} player rating rows for {fmt} on {snapshot_date}.", "success")
        return redirect(url_for("rankings", tab="players", format=fmt))
    except (OperationError, Exception) as e:
        flash(f"Failed to load snapshot: {e}", "danger")
        return redirect(url_for("admin", action="load_snapshot"))


# I3: Register Player
@app.route("/admin/player/add", methods=["POST"])
def admin_register_player():
    first_name = request.form.get("first_name")
    last_name = request.form.get("last_name")
    dob = request.form.get("date_of_birth")
    gender = request.form.get("gender")
    team_code = request.form.get("team_code")

    try:
        new_id = ops.register_player(first_name, last_name, dob, gender, team_code)
        flash(f"Successfully registered player {first_name} {last_name} (#{new_id}) for {team_code}.", "success")
        return redirect(url_for("player_details", player_id=new_id))
    except (OperationError, Exception) as e:
        flash(f"Failed to register player: {e}", "danger")
        return redirect(url_for("admin", action="player_add"))


# U1: Record Match Result & (Optionally) Add Rating Snapshot
@app.route("/admin/match/<int:match_id>/result", methods=["POST"])
def admin_record_result(match_id):
    result = request.form.get("result")
    winner_code = request.form.get("winner_code") or None
    margin_value = request.form.get("margin_value") or None
    margin_type = request.form.get("margin_type") or None

    effective_date = request.form.get("effective_date") or None
    team1_code = request.form.get("team1_code")
    team1_pts = request.form.get("team1_points")
    team2_code = request.form.get("team2_code")
    team2_pts = request.form.get("team2_points")

    points_added = None
    if team1_code and team1_pts and team2_code and team2_pts:
        points_added = {
            team1_code: int(team1_pts.strip()),
            team2_code: int(team2_pts.strip()),
        }

    try:
        ops.record_result(
            match_id=match_id,
            result=result,
            winner_code=winner_code,
            margin_value=margin_value,
            margin_type=margin_type,
            points_added=points_added,
            effective_date=effective_date,
        )
        flash(f"Successfully recorded result for Match #{match_id}.", "success")
        return redirect(url_for("match_details", match_id=match_id))
    except (OperationError, Exception) as e:
        flash(f"Failed to record result: {e}", "danger")
        return redirect(url_for("match_details", match_id=match_id))


# U2: Correct Result After Ruling
@app.route("/admin/match/<int:match_id>/correct", methods=["POST"])
def admin_correct_result(match_id):
    result = request.form.get("result")
    winner_code = request.form.get("winner_code") or None
    margin_value = request.form.get("margin_value") or None
    margin_type = request.form.get("margin_type") or None

    revised_points = {}
    for key, val in request.form.items():
        if key.startswith("revised_pts_"):
            # Format: revised_pts_<CODE>_<YYYY-MM-DD>
            parts = key.split("_", 3)
            if len(parts) == 4 and val.strip():
                code = parts[2]
                date_str = parts[3]
                revised_points[(code, date_str)] = int(val.strip())

    try:
        ops.correct_result(
            match_id=match_id,
            result=result,
            winner_code=winner_code,
            margin_value=margin_value,
            margin_type=margin_type,
            revised_points=revised_points,
        )
        flash(f"Successfully corrected result for Match #{match_id} and revised subsequent ratings.", "success")
        return redirect(url_for("match_details", match_id=match_id))
    except (OperationError, Exception) as e:
        flash(f"Failed to correct result: {e}", "danger")
        return redirect(url_for("match_details", match_id=match_id))


# U3: Record Retirement
@app.route("/admin/player/<int:player_id>/retire", methods=["POST"])
def admin_record_retirement(player_id):
    fmt = request.form.get("format")
    try:
        ops.record_retirement(player_id, fmt)
        flash(f"Recorded retirement from {fmt} for Player #{player_id}.", "success")
    except (OperationError, Exception) as e:
        flash(f"Failed to record retirement: {e}", "danger")
    return redirect(url_for("player_details", player_id=player_id))


# U4: Change Team's Eligible Formats
@app.route("/admin/team/formats", methods=["POST"])
def admin_set_team_formats():
    team_code = request.form.get("team_code")
    formats = request.form.getlist("formats[]")
    try:
        ops.set_eligible_formats(team_code, formats)
        flash(f"Updated eligible formats for {team_code} to: {', '.join(formats)}.", "success")
    except (OperationError, Exception) as e:
        flash(f"Failed to update team formats: {e}", "danger")
    return redirect(url_for("teams"))


# U5: Move Player to Another Team
@app.route("/admin/player/<int:player_id>/move", methods=["POST"])
def admin_move_player(player_id):
    new_team = request.form.get("new_team_code")
    try:
        ops.move_player(player_id, new_team)
        flash(f"Transferred Player #{player_id} to team {new_team}.", "success")
    except (OperationError, Exception) as e:
        flash(f"Failed to move player: {e}", "danger")
    return redirect(url_for("player_details", player_id=player_id))


# D1: Delete Match Entered in Error
@app.route("/admin/match/<int:match_id>/delete", methods=["POST"])
def admin_delete_match(match_id):
    try:
        ops.delete_match(match_id)
        flash(f"Deleted Match #{match_id} (and associated contests/lineups).", "success")
        return redirect(url_for("matches"))
    except (OperationError, Exception) as e:
        flash(f"Failed to delete match: {e}", "danger")
        return redirect(url_for("match_details", match_id=match_id))


# D2: Move Appearances
@app.route("/admin/player/move-appearances", methods=["POST"])
def admin_move_appearances():
    from_id = request.form.get("from_player_id")
    to_id = request.form.get("to_player_id")
    try:
        count = ops.move_appearances(int(from_id), int(to_id))
        flash(f"Moved {count} match appearances from Player #{from_id} to #{to_id}.", "success")
        return redirect(url_for("player_details", player_id=to_id))
    except (OperationError, Exception) as e:
        flash(f"Failed to move appearances: {e}", "danger")
        return redirect(url_for("admin", action="player_dup"))


# D2: Delete Player
@app.route("/admin/player/<int:player_id>/delete", methods=["POST"])
def admin_delete_player(player_id):
    try:
        ops.delete_player(player_id)
        flash(f"Deleted Player #{player_id}.", "success")
        return redirect(url_for("players"))
    except (OperationError, Exception) as e:
        flash(f"Failed to delete player: {e}", "danger")
        return redirect(url_for("player_details", player_id=player_id))


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
