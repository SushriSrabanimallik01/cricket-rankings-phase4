# ICC Cricket Rankings Web Application (Phase 4)

**Course:** Data & Applications  
**Mini-World Domain:** Domain 3 &mdash; ICC Cricket Rankings (`icc-cricket.com/rankings`)  
**Implementation Team:** Team 38  

---

## 1. Paradigm, DBMS & Tech Stack

- **Database Paradigm:** Relational Model
- **DBMS:** MySQL 8.0+ (`utf8mb4` character set, InnoDB engine)
- **Database Driver:** `PyMySQL` (v1.1+) using raw, parameterized SQL queries (`%s` placeholders, autocommit=False)
- **Backend Framework:** Python 3.10+ with Flask (v3.0+)
- **Frontend Stack:** Server-rendered Jinja2 templates, modern responsive CSS3, vanilla JavaScript (ES6)
- **Testing Framework:** Python standard library `unittest` & `pytest`

---

## 2. Design Changes vs Phase 3


### Detailed Changes & Reasons

| # | Component Changed | Change Description | One-line Reason |
|---|---|---|---|
| 1 | Table Name: `MATCH` &rarr; `CricketMatch` | Renamed the entity table from `MATCH` to `CricketMatch` | `MATCH` is a reserved SQL keyword in MySQL 8.0+. |
| 2 | Table: `Parameter` | Added a parameter table (`ParamName`, `ParamValue`) | Stores dynamic business parameters (qualifying window months, list sizes) as data instead of hardcoding in triggers. |
| 3 | Derived Attribute Views | Created `v_team_rating`, `v_latest_team_rating`, `v_player_rating`, `v_latest_player_rating` | Computes Rating, Position, All-Rounder Index, and Ranks dynamically without storing redundant derived values. |
| 4 | Constraint C1 & C2 (Ranges) | Added `CHECK` constraints on ratings and points | Ensures Batting/Bowling points are 0&ndash;1000 and Team points &ge; 0, matches &ge; 1. |
| 5 | Constraint C4 (Dates & Conditions) | Added triggers on `CricketMatch` and `Player` | Guarantees birth date is in the past, match dates lie within series dates, and end date &ge; start date. |
| 6 | Constraint C6 (Two Teams) | Enforced in `Contests` trigger and `operations.add_match` transaction | Ensures every match has exactly two distinct contesting teams. |
| 7 | Constraint C7 (Complementary Outcomes) | Added stored procedure `sp_check_outcome` and triggers on `Contests` | Restricts outcomes to Win/Loss, Tie/Tie, Draw/Draw (Test only), or NoResult/NoResult, and records margin only for Wins. |
| 8 | Constraint C8 (Format Eligibility) | Added function `fn_team_eligible` and trigger on `Contests` / `TeamRating` | Prevents teams from playing or receiving ratings in formats they are not eligible for. |
| 9 | Constraint C9 (No Overlapping Matches) | Added trigger on `Contests` checking existing match date ranges | Blocks a national team from contesting two matches simultaneously on overlapping calendar dates. |
| 10 | Constraint C10 (Playing Squad Consistency) | Composite foreign key `(MatchID, ICC_Code)` on `PlaysIn` | Guarantees that players only appear for one of the two contesting teams of that match. |
| 11 | Constraint C11 & C12 (Snapshot Rules) | Added trigger `trg_playerrating_bi` and `trg_teamrating_bi` | Enforces Wednesday snapshots for men, Tuesday for women, monotonic team snapshot dates, and forbids women's Test tables. |
| 12 | Constraint C13 & C14 (Window & Size Caps) | Added appearance window validation and 100-player limit | Restricts player rankings to active unretired cricketers appearing in the format within the qualifying window. |
| 13 | Constraint C15 (Recursive Qualifiers) | Added trigger on `Series` for `QUALIFIES_FOR` | Enforces that qualifier series share format and gender, end before the main event begins, and prevents self-qualification. |
| 14 | Constraint C16 (Referential Actions) | Defined `ON DELETE CASCADE` for match child records and `RESTRICT` for referenced players/teams | Ensures clean cascading deletions of match details while preventing orphaned appearances. |

---

## 3. Setup and Run Instructions

### Step 1: Database Setup
Make sure MySQL server (v8.0+) is running. Run the schema creation and data population scripts from the repository root:

```bash
# 1. Create database schema, tables, views, triggers and constraints
mysql -u root -p < src/schema.sql

# 2. Populate comprehensive real-world cricket data
mysql -u root -p < src/populate.sql
```

### Step 2: Install Python Dependencies
Create a virtual environment (optional) and install the required packages:

```bash
python3 -m venv venv
source venv/bin/activate   # On Windows: venv\Scripts\activate

pip install -r src/requirements.txt
```

### Step 3: Environment Configuration (Optional)
If your MySQL credentials differ from `root` with no password on `localhost:3306`, configure `.env` (copy from `.env.example`):

```bash
cp .env.example .env
# Edit .env with your DB_HOST, DB_USER, DB_PASS, DB_PORT, or DB_SOCKET
```

### Step 4: Run the Application
Start the Flask web server:

```bash
cd src
python3 app.py
```

The application will be running at: **`http://localhost:5000`**

### Step 5: Run Automated Unit Tests
To run the automated test suite verifying database configuration, query purity, and business operations:

```bash
python3 -m unittest discover -s tests
```

---

## 4. Feature List & Demonstration Walkthrough

The numbered feature list below directly follows the demonstration flow for the video presentation:

### Part 1: Update Operations (Demonstrated in DB Shell & Web UI)

1. **[I1] Schedule / Add a Match:**
   - **Location:** Admin Portal &rarr; Add Match (`/admin?action=match_add`) or Matches page header button.
   - **Trigger:** Fill the form with Series, Venue, Team 1, Team 2, Start Date, End Date, and format condition (Scheduled days for Test or Overs for limited-overs). Click "Add Match".
   - **Result:** Inserts a new `CricketMatch`, the subclass record (`TestMatch` or `LimitedOversMatch`), and exactly two `Contests` rows. Enforces C4, C6, C8, and C9. Redirects to the Match Details page.

2. **[U1] Record Match Result & Update Team Ratings:**
   - **Location:** Match Details page (`/matches/<id>`) &rarr; Record Result button, or Admin Portal (`/admin?action=result&match_id=<id>`).
   - **Trigger:** Choose outcome (Win, Tie, Draw, NoResult), specify Winner and Margin (Value & Type), and optionally provide points added to publish a new rating snapshot.
   - **Result:** Atomically updates `Contests` and `CricketMatch`. Enforces C7 (complementary results and winner/margin check). If rating points are entered, publishes a new `TeamRating` snapshot where matches rise by 1 and position recalculates dynamically.

3. **[U2] Correct Result After a Ruling:**
   - **Location:** Match Details page (`/matches/<id>`) &rarr; Correct Result button, or Admin Portal (`/admin?action=correct_result&match_id=<id>`).
   - **Trigger:** Select the match, choose the corrected outcome and winner, and supply revised Points for each subsequent snapshot of the two teams. Click "Apply Result Correction".
   - **Result:** Updates match outcomes and updates `TeamRating.Points` for all subsequent dated snapshots, leaving earlier snapshots intact.

4. **[U3] Record Player Retirement:**
   - **Location:** Player Profile page (`/players/<id>`) &rarr; Record Retirement button, or Admin Portal (`/admin?action=retire&player_id=<id>`).
   - **Trigger:** Select player and format (Test, ODI, T20I), submit form.
   - **Result:** Trigger verifies player has match appearances in that format. Populates `RetiredFormat1-3`. The player immediately drops out of current rankings tables (H4) while past snapshot history is preserved.

5. **[U4] Change Team Eligible Formats:**
   - **Location:** Teams page (`/teams`) &rarr; Manage Formats button, or Admin Portal (`/admin?action=team_formats`).
   - **Trigger:** Select team and toggle checkboxes for 1 to 3 formats (Test, ODI, T20I).
   - **Result:** Updates `Team.EligibleFormat1-3`. Future matches or snapshots in excluded formats will be blocked by constraint C8.

6. **[U5] Transfer Player to Another Team:**
   - **Location:** Player Profile page (`/players/<id>`) &rarr; Transfer Team button, or Admin Portal (`/admin?action=player_move&player_id=<id>`).
   - **Trigger:** Choose target destination team and submit.
   - **Result:** Updates `Player.ICC_Code` (REPRESENTS relationship). All historical `PlaysIn` rows remain bound to the team the player represented at match time.

7. **[D1] Delete Match Entered in Error:**
   - **Location:** Match Details page (`/matches/<id>`) &rarr; Delete Match button, or Admin Portal (`/admin?action=match_delete`).
   - **Trigger:** Select match and click "Permanently Delete Match".
   - **Result:** Performs `DELETE FROM CricketMatch`. Foreign key actions automatically CASCADE delete child records in `Contests`, `PlaysIn`, and `TestMatch`/`LimitedOversMatch`.

8. **[D2] Move Appearances & Delete Duplicate Player:**
   - **Location:** Admin Portal &rarr; Deduplicate Player (`/admin?action=player_dup`).
   - **Trigger:** Step 1 moves appearances (`PlaysIn`) from duplicate player to surviving player. Step 2 deletes the duplicate player.
   - **Result:** Successfully cascades player rating rows while preventing deletion if unresolved match appearances exist (referential integrity).

---

### Part 2: Query Operations & Browsing Interface

9. **[P1 / H2] Team Rankings Table & Historical Date Lookup:**
   - **Location:** Rankings Hub &rarr; Team Rankings (`/rankings?tab=teams`).
   - **Trigger:** Switch format (Test, ODI, T20I) or gender (Men, Women). Use the "Snapshot on or before" date picker to view past tables (H2).
   - **Result:** Returns official rank, team name, matches, points, and rating ordered by position.

10. **[A2] League Average Rating:**
    - **Location:** Rankings Hub &rarr; Team Rankings header (`/rankings?tab=teams`).
    - **Trigger:** Displays automatically on table selection.
    - **Result:** Calculates the league average rating and total teams in the latest snapshot.

11. **[P1 / H4] Player Rankings Table:**
    - **Location:** Rankings Hub &rarr; Player Rankings (`/rankings?tab=players`).
    - **Trigger:** Choose Format, Gender, and Category (Batting, Bowling, All-Rounder). Optional past date filter (H4).
    - **Result:** Lists top-100 ranked athletes with rating points / all-rounder index, filtering out retired players.

12. **[H1 / H5] Team Rating History & Position Movement:**
    - **Location:** Rankings Hub &rarr; Rating History (`/rankings?tab=history`).
    - **Trigger:** Select a team and format.
    - **Result:** Displays full historical snapshot progression (H1) and the exact snapshot dates where table position shifted (H5).

13. **[H6] Team Rating Comparison Between Two Dates:**
    - **Location:** Rankings Hub &rarr; Rating History (`/rankings?tab=history`).
    - **Trigger:** Enter two dates (e.g. `2026-01-02` and `2026-11-01`).
    - **Result:** Displays each team's rating at both dates and calculates net rise/fall sorted by largest rise first.

14. **[R3] 1-Year Rating Movement & Matches Played:**
    - **Location:** Rankings Hub &rarr; Rating History (`/rankings?tab=history`).
    - **Trigger:** Choose format and gender.
    - **Result:** Compares current ratings with the snapshot closest to 1 year prior and calculates matches played in between.

15. **[A1 / R1 / R4 / R5] Analyst Reports Hub:**
    - **Location:** Rankings Hub &rarr; Analyst Reports (`/rankings?tab=analyst`) or Dashboard (`/`).
    - **Trigger:** Click tab to view:
      - **A1:** All-time peak batting points recorded in each format.
      - **R1:** Top 10 batters per format and gender.
      - **R4:** World-class all-rounders with index &gt; 300.
      - **R5:** Deep benches (nations with more batters listed than average).

16. **[S1 / A4] Teams Directory & Squad Profile:**
    - **Location:** Teams page (`/teams`).
    - **Trigger:** Filter by format eligibility (Test, ODI, T20I).
    - **Result:** Displays teams, eligible formats, squad counts, and squad profile (youngest and oldest player ages).

17. **[Q1 / S3] Player Directory & Search:**
    - **Location:** Players page (`/players`).
    - **Trigger:** Type partial search term in search bar (e.g. "SHA") or choose a national squad (S3).
    - **Result:** Case-insensitive search on first and last name, displaying age, current team, and retirement status.

18. **[H3 / PlaysIn] Player Profile & Rating Progression:**
    - **Location:** Player details page (`/players/<id>`).
    - **Trigger:** Click on any player name across the site.
    - **Result:** Full profile, historical rating progression across Test, ODI, and T20I formats, and complete match appearance record with captaincy indicators.

19. **[Q2 / A3 / S2 / R6] Series Explorer & Event Pipeline:**
    - **Location:** Series page (`/series`).
    - **Trigger:** Search series name (Q2 e.g. "World Cup"), select a series to view fixtures (S2), or view the ICC Event Qualifier Pipeline (R6).
    - **Result:** Displays series match counts (A3), date-ordered fixtures (S2), and recursive qualifiers feeding main ICC events (R6).

20. **[P3 / Q3] Venues Finder:**
    - **Location:** Venues page (`/venues`).
    - **Trigger:** Filter by country (P3) or search by city (Q3 e.g. "COL").
    - **Result:** Shows stadium names, city, country, and derived count of matches hosted.

21. **[R2 / R7] Multi-Entity Statistical Reports:**
    - **Location:** Reports page (`/reports`).
    - **Trigger:** Select format and date range.
    - **Result:** Results against rating (R2) showing wins, losses, ties, draws, and no-results alongside latest rating; and players who changed national allegiance (R7).
