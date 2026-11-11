-- =====================================================================
-- schema.sql  |  Team 38  |  ICC Cricket Rankings (MySQL 8.0+)
-- Run with:  mysql -u <user> -p < schema.sql
-- Baseline: Phase 3 relational model (Team 25) + Phase 1 constraints
-- (C1-C16) restored as CHECKs, triggers and views.
-- Design changes vs Phase 3 are listed in README.md.
-- =====================================================================

DROP DATABASE IF EXISTS icc_rankings_db;
CREATE DATABASE icc_rankings_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE icc_rankings_db;

-- ---------------------------------------------------------------------
-- 0. Parameters (C13 qualifying windows, C14 list size) kept as data
-- ---------------------------------------------------------------------
CREATE TABLE Parameter (
    ParamName  VARCHAR(40) PRIMARY KEY,
    ParamValue INT NOT NULL CHECK (ParamValue > 0)
);

INSERT INTO Parameter (ParamName, ParamValue) VALUES
    ('QUALIFY_MONTHS_TEST', 12),
    ('QUALIFY_MONTHS_ODI',   9),
    ('QUALIFY_MONTHS_T20I',  9),
    ('MAX_LIST_SIZE',      100);

-- ---------------------------------------------------------------------
-- 1. Core tables
-- ---------------------------------------------------------------------
CREATE TABLE Venue (
    VenueID   INT AUTO_INCREMENT PRIMARY KEY,
    VenueName VARCHAR(120) NOT NULL,
    City      VARCHAR(60)  NOT NULL,
    Country   VARCHAR(60)  NOT NULL,
    CONSTRAINT uq_venue UNIQUE (VenueName, City)
);
CREATE INDEX idx_venue_country ON Venue (Country);
CREATE INDEX idx_venue_city    ON Venue (City);

-- Phase 3 option 4(a): multi-valued EligibleFormats -> 3 columns
CREATE TABLE Team (
    ICC_Code        VARCHAR(3)  PRIMARY KEY,
    TeamName        VARCHAR(60) NOT NULL UNIQUE,
    EligibleFormat1 ENUM('Test','ODI','T20I') NOT NULL,
    EligibleFormat2 ENUM('Test','ODI','T20I') NULL,
    EligibleFormat3 ENUM('Test','ODI','T20I') NULL,
    CONSTRAINT ck_team_code CHECK (REGEXP_LIKE(ICC_Code, '^[A-Z]{1,3}$', 'c')),
    CONSTRAINT ck_team_fmt2 CHECK (EligibleFormat2 IS NULL OR EligibleFormat2 <> EligibleFormat1),
    CONSTRAINT ck_team_fmt3 CHECK (EligibleFormat3 IS NULL
                                   OR (EligibleFormat3 <> EligibleFormat1
                                       AND (EligibleFormat2 IS NULL OR EligibleFormat3 <> EligibleFormat2)))
);

CREATE TABLE Series (
    SeriesID    INT AUTO_INCREMENT PRIMARY KEY,
    SeriesName  VARCHAR(150) NOT NULL,
    SeriesType  ENUM('Bilateral','League','Qualifier','ICC Event') NOT NULL,
    Gender      ENUM('Men','Women') NOT NULL,
    Format      ENUM('Test','ODI','T20I') NOT NULL,
    StartDate   DATE NOT NULL,
    EndDate     DATE NOT NULL,
    MainEventID INT NULL,
    CONSTRAINT uq_series UNIQUE (SeriesName, StartDate),
    CONSTRAINT ck_series_dates CHECK (EndDate >= StartDate),
    CONSTRAINT ck_series_no_women_test CHECK (NOT (Gender = 'Women' AND Format = 'Test')),
    CONSTRAINT fk_series_main FOREIGN KEY (MainEventID) REFERENCES Series (SeriesID)
        ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX idx_series_fmt_gender ON Series (Format, Gender);
CREATE INDEX idx_series_name       ON Series (SeriesName);

-- MATCH is a reserved word in MySQL, so the table is CricketMatch
CREATE TABLE CricketMatch (
    MatchID     INT AUTO_INCREMENT PRIMARY KEY,
    StartDate   DATE NOT NULL,
    EndDate     DATE NOT NULL,
    MarginValue INT NULL,
    MarginType  ENUM('Runs','Wickets','InningsAndRuns') NULL,
    VenueID     INT NOT NULL,
    SeriesID    INT NOT NULL,
    CONSTRAINT ck_match_dates  CHECK (EndDate >= StartDate),
    CONSTRAINT ck_match_margin CHECK (
        (MarginValue IS NULL AND MarginType IS NULL)
        OR (MarginValue > 0 AND MarginType IS NOT NULL)),
    CONSTRAINT fk_match_venue  FOREIGN KEY (VenueID)  REFERENCES Venue (VenueID)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_match_series FOREIGN KEY (SeriesID) REFERENCES Series (SeriesID)
        ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX idx_match_dates ON CricketMatch (StartDate, EndDate);

-- Specialisation (option 8A): subclass key is both PK and FK
CREATE TABLE TestMatch (
    MatchID       INT PRIMARY KEY,
    ScheduledDays TINYINT NOT NULL,
    CONSTRAINT ck_test_days CHECK (ScheduledDays IN (4, 5)),
    CONSTRAINT fk_test_match FOREIGN KEY (MatchID) REFERENCES CricketMatch (MatchID)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE LimitedOversMatch (
    MatchID      INT PRIMARY KEY,
    OversPerSide TINYINT NOT NULL,
    DLSApplied   BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_lom_overs CHECK (OversPerSide IN (20, 50)),
    CONSTRAINT fk_lom_match FOREIGN KEY (MatchID) REFERENCES CricketMatch (MatchID)
        ON DELETE CASCADE ON UPDATE CASCADE
);

-- Phase 3 option 4(a): multi-valued RetiredFormats -> 3 columns
CREATE TABLE Player (
    PlayerID       INT AUTO_INCREMENT PRIMARY KEY,
    FirstName      VARCHAR(60) NOT NULL,
    LastName       VARCHAR(60) NOT NULL,
    DateOfBirth    DATE NOT NULL,
    Gender         ENUM('Men','Women') NOT NULL,
    RetiredFormat1 ENUM('Test','ODI','T20I') NULL,
    RetiredFormat2 ENUM('Test','ODI','T20I') NULL,
    RetiredFormat3 ENUM('Test','ODI','T20I') NULL,
    ICC_Code       VARCHAR(3) NOT NULL,
    CONSTRAINT ck_player_first CHECK (CHAR_LENGTH(TRIM(FirstName)) > 0),
    CONSTRAINT ck_player_last  CHECK (CHAR_LENGTH(TRIM(LastName))  > 0),
    CONSTRAINT fk_player_team FOREIGN KEY (ICC_Code) REFERENCES Team (ICC_Code)
        ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX idx_player_name ON Player (LastName, FirstName);

-- ---------------------------------------------------------------------
-- 2. Relationship tables
-- ---------------------------------------------------------------------
-- CONTESTS (M:N). Outcome is NULL until the result is recorded (U1).
CREATE TABLE Contests (
    MatchID  INT        NOT NULL,
    ICC_Code VARCHAR(3) NOT NULL,
    Outcome  ENUM('Win','Loss','Tie','Draw','NoResult') NULL,
    PRIMARY KEY (MatchID, ICC_Code),
    CONSTRAINT fk_contests_match FOREIGN KEY (MatchID) REFERENCES CricketMatch (MatchID)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_contests_team  FOREIGN KEY (ICC_Code) REFERENCES Team (ICC_Code)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- PLAYS_IN (ternary). PK (PlayerID, MatchID); the composite FK to CONTESTS
-- implements C10 (team must be one of the two teams of the match) and
-- already covers the MatchID and ICC_Code references.
CREATE TABLE PlaysIn (
    PlayerID  INT        NOT NULL,
    MatchID   INT        NOT NULL,
    ICC_Code  VARCHAR(3) NOT NULL,
    IsCaptain BOOLEAN    NOT NULL DEFAULT FALSE,
    PRIMARY KEY (PlayerID, MatchID),
    CONSTRAINT fk_playsin_player  FOREIGN KEY (PlayerID) REFERENCES Player (PlayerID)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_playsin_contest FOREIGN KEY (MatchID, ICC_Code) REFERENCES Contests (MatchID, ICC_Code)
        ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX idx_playsin_team ON PlaysIn (ICC_Code);

-- ---------------------------------------------------------------------
-- 3. Weak entities (snapshots)
-- ---------------------------------------------------------------------
CREATE TABLE TeamRating (
    ICC_Code      VARCHAR(3) NOT NULL,
    Format        ENUM('Test','ODI','T20I') NOT NULL,
    Gender        ENUM('Men','Women') NOT NULL,
    EffectiveDate DATE NOT NULL,
    Matches       INT NOT NULL,
    Points        INT NOT NULL,
    PRIMARY KEY (ICC_Code, Format, Gender, EffectiveDate),
    CONSTRAINT ck_tr_matches CHECK (Matches >= 1),
    CONSTRAINT ck_tr_points  CHECK (Points >= 0),
    CONSTRAINT ck_tr_women_test CHECK (NOT (Gender = 'Women' AND Format = 'Test')),
    CONSTRAINT fk_tr_team FOREIGN KEY (ICC_Code) REFERENCES Team (ICC_Code)
        ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX idx_tr_table ON TeamRating (Format, Gender, EffectiveDate);

CREATE TABLE PlayerRating (
    PlayerID      INT NOT NULL,
    Format        ENUM('Test','ODI','T20I') NOT NULL,
    SnapshotDate  DATE NOT NULL,
    BattingPoints INT NULL,
    BowlingPoints INT NULL,
    PRIMARY KEY (PlayerID, Format, SnapshotDate),
    CONSTRAINT ck_pr_bat  CHECK (BattingPoints IS NULL OR BattingPoints BETWEEN 0 AND 1000),
    CONSTRAINT ck_pr_bowl CHECK (BowlingPoints IS NULL OR BowlingPoints BETWEEN 0 AND 1000),
    CONSTRAINT ck_pr_any  CHECK (BattingPoints IS NOT NULL OR BowlingPoints IS NOT NULL),
    CONSTRAINT fk_pr_player FOREIGN KEY (PlayerID) REFERENCES Player (PlayerID)
        ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX idx_pr_table ON PlayerRating (Format, SnapshotDate);

-- ---------------------------------------------------------------------
-- 4. Helper functions and procedure
--    @bulk_load = 1 (set only by populate.sql) skips two checks that need
--    full line-up history: C13 window check and margin-on-insert.
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_param(p_name VARCHAR(40)) RETURNS INT
    DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v INT;
    SELECT ParamValue INTO v FROM Parameter WHERE ParamName = p_name;
    RETURN v;
END$$

CREATE FUNCTION fn_team_eligible(p_code VARCHAR(3), p_fmt VARCHAR(10)) RETURNS TINYINT(1)
    DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v INT DEFAULT 0;
    SELECT COUNT(*) INTO v FROM Team
     WHERE ICC_Code = p_code
       AND p_fmt IN (EligibleFormat1, EligibleFormat2, EligibleFormat3);
    RETURN v > 0;
END$$

CREATE FUNCTION fn_player_retired(p_id INT, p_fmt VARCHAR(10)) RETURNS TINYINT(1)
    DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v INT DEFAULT 0;
    SELECT COUNT(*) INTO v FROM Player
     WHERE PlayerID = p_id
       AND p_fmt IN (RetiredFormat1, RetiredFormat2, RetiredFormat3);
    RETURN v > 0;
END$$

CREATE FUNCTION fn_player_appeared(p_id INT, p_fmt VARCHAR(10)) RETURNS TINYINT(1)
    DETERMINISTIC READS SQL DATA
BEGIN
    DECLARE v INT DEFAULT 0;
    SELECT COUNT(*) INTO v
      FROM PlaysIn pi
      JOIN CricketMatch m ON m.MatchID = pi.MatchID
      JOIN Series s ON s.SeriesID = m.SeriesID
     WHERE pi.PlayerID = p_id AND s.Format = p_fmt;
    RETURN v > 0;
END$$

-- C7: outcomes must be complementary; Draw only in Tests
CREATE PROCEDURE sp_check_outcome(IN p_match INT, IN p_team VARCHAR(3), IN p_outcome VARCHAR(10))
BEGIN
    DECLARE v_fmt VARCHAR(10);
    DECLARE v_other VARCHAR(10);
    IF p_outcome IS NOT NULL THEN
        SELECT s.Format INTO v_fmt
          FROM CricketMatch m JOIN Series s ON s.SeriesID = m.SeriesID
         WHERE m.MatchID = p_match;
        IF p_outcome = 'Draw' AND v_fmt IS NOT NULL AND v_fmt <> 'Test' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C7: a Draw is only possible in a Test match';
        END IF;
        SELECT MAX(Outcome) INTO v_other FROM Contests
         WHERE MatchID = p_match AND ICC_Code <> p_team;
        IF v_other IS NOT NULL THEN
            IF NOT ((p_outcome = 'Win'  AND v_other = 'Loss')
                 OR (p_outcome = 'Loss' AND v_other = 'Win')
                 OR (p_outcome = v_other AND p_outcome IN ('Tie','Draw','NoResult'))) THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'C7: outcomes must be complementary (Win/Loss, Tie/Tie, Draw/Draw, NoResult/NoResult)';
            END IF;
        END IF;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 5. Triggers
-- ---------------------------------------------------------------------

-- C4 date of birth in the past; C13/U3 retirement only after an appearance
CREATE TRIGGER trg_player_bi BEFORE INSERT ON Player FOR EACH ROW
BEGIN
    IF NEW.DateOfBirth >= CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C4: date of birth must be in the past';
    END IF;
END$$

CREATE TRIGGER trg_player_bu BEFORE UPDATE ON Player FOR EACH ROW
BEGIN
    IF NEW.DateOfBirth >= CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C4: date of birth must be in the past';
    END IF;
    IF NEW.RetiredFormat1 IS NOT NULL AND NOT (OLD.RetiredFormat1 <=> NEW.RetiredFormat1)
       AND NOT fn_player_appeared(NEW.PlayerID, NEW.RetiredFormat1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'U3: cannot retire from a format the player has not appeared in';
    END IF;
    IF NEW.RetiredFormat2 IS NOT NULL AND NOT (OLD.RetiredFormat2 <=> NEW.RetiredFormat2)
       AND NOT fn_player_appeared(NEW.PlayerID, NEW.RetiredFormat2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'U3: cannot retire from a format the player has not appeared in';
    END IF;
    IF NEW.RetiredFormat3 IS NOT NULL AND NOT (OLD.RetiredFormat3 <=> NEW.RetiredFormat3)
       AND NOT fn_player_appeared(NEW.PlayerID, NEW.RetiredFormat3) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'U3: cannot retire from a format the player has not appeared in';
    END IF;
END$$

-- C15 QUALIFIES_FOR: same gender and format, qualifier ends before main event
-- starts, no self-reference
CREATE TRIGGER trg_series_bi BEFORE INSERT ON Series FOR EACH ROW
BEGIN
    DECLARE v_g VARCHAR(10);
    DECLARE v_f VARCHAR(10);
    DECLARE v_start DATE;
    IF NEW.MainEventID IS NOT NULL THEN
        SELECT Gender, Format, StartDate INTO v_g, v_f, v_start
          FROM Series WHERE SeriesID = NEW.MainEventID;
        IF v_g <> NEW.Gender OR v_f <> NEW.Format THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C15: qualifier and main event must share gender and format';
        END IF;
        IF NEW.EndDate >= v_start THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C15: qualifier must end before the main event starts';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_series_bu BEFORE UPDATE ON Series FOR EACH ROW
BEGIN
    DECLARE v_g VARCHAR(10);
    DECLARE v_f VARCHAR(10);
    DECLARE v_start DATE;
    IF NEW.MainEventID IS NOT NULL THEN
        IF NEW.MainEventID = NEW.SeriesID THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C15: a series cannot qualify for itself';
        END IF;
        SELECT Gender, Format, StartDate INTO v_g, v_f, v_start
          FROM Series WHERE SeriesID = NEW.MainEventID;
        IF v_g <> NEW.Gender OR v_f <> NEW.Format THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C15: qualifier and main event must share gender and format';
        END IF;
        IF NEW.EndDate >= v_start THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C15: qualifier must end before the main event starts';
        END IF;
    END IF;
END$$

-- C4 match inside its series dates; C7 margin only with a winner
CREATE TRIGGER trg_match_bi BEFORE INSERT ON CricketMatch FOR EACH ROW
BEGIN
    DECLARE v_s DATE;
    DECLARE v_e DATE;
    SELECT StartDate, EndDate INTO v_s, v_e FROM Series WHERE SeriesID = NEW.SeriesID;
    IF v_s IS NOT NULL AND (NEW.StartDate < v_s OR NEW.EndDate > v_e) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C4: match dates must lie within the series dates';
    END IF;
    IF NEW.MarginValue IS NOT NULL AND COALESCE(@bulk_load, 0) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C7: record the margin through the result update, after a winner exists';
    END IF;
END$$

CREATE TRIGGER trg_match_bu BEFORE UPDATE ON CricketMatch FOR EACH ROW
BEGIN
    DECLARE v_s DATE;
    DECLARE v_e DATE;
    DECLARE v_w INT DEFAULT 0;
    SELECT StartDate, EndDate INTO v_s, v_e FROM Series WHERE SeriesID = NEW.SeriesID;
    IF v_s IS NOT NULL AND (NEW.StartDate < v_s OR NEW.EndDate > v_e) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C4: match dates must lie within the series dates';
    END IF;
    IF NEW.MarginValue IS NOT NULL THEN
        SELECT COUNT(*) INTO v_w FROM Contests WHERE MatchID = NEW.MatchID AND Outcome = 'Win';
        IF v_w = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C7: a margin is recorded only for a match with a winner';
        END IF;
    END IF;
END$$

-- Subclass consistency with the series format (disjoint, total specialisation)
CREATE TRIGGER trg_testmatch_bi BEFORE INSERT ON TestMatch FOR EACH ROW
BEGIN
    DECLARE v_fmt VARCHAR(10);
    SELECT s.Format INTO v_fmt FROM CricketMatch m JOIN Series s ON s.SeriesID = m.SeriesID
     WHERE m.MatchID = NEW.MatchID;
    IF v_fmt IS NOT NULL AND v_fmt <> 'Test' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A TestMatch must belong to a Test series';
    END IF;
END$$

CREATE TRIGGER trg_lom_bi BEFORE INSERT ON LimitedOversMatch FOR EACH ROW
BEGIN
    DECLARE v_fmt VARCHAR(10);
    SELECT s.Format INTO v_fmt FROM CricketMatch m JOIN Series s ON s.SeriesID = m.SeriesID
     WHERE m.MatchID = NEW.MatchID;
    IF v_fmt = 'Test' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A limited-overs match cannot belong to a Test series';
    END IF;
    IF (v_fmt = 'ODI' AND NEW.OversPerSide <> 50) OR (v_fmt = 'T20I' AND NEW.OversPerSide <> 20) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C4: OversPerSide must be 50 for an ODI and 20 for a T20I';
    END IF;
END$$

-- C6 (at most two teams; app transaction ensures exactly two), C8, C9, C7
CREATE TRIGGER trg_contests_bi BEFORE INSERT ON Contests FOR EACH ROW
BEGIN
    DECLARE v_fmt VARCHAR(10);
    DECLARE v_start DATE;
    DECLARE v_end DATE;
    DECLARE v_cnt INT DEFAULT 0;
    DECLARE v_ov INT DEFAULT 0;
    SELECT s.Format, m.StartDate, m.EndDate INTO v_fmt, v_start, v_end
      FROM CricketMatch m JOIN Series s ON s.SeriesID = m.SeriesID
     WHERE m.MatchID = NEW.MatchID;
    SELECT COUNT(*) INTO v_cnt FROM Contests WHERE MatchID = NEW.MatchID;
    IF v_cnt >= 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C6: a match has exactly two teams';
    END IF;
    IF v_fmt IS NOT NULL AND NOT fn_team_eligible(NEW.ICC_Code, v_fmt) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C8: team is not eligible for this format';
    END IF;
    IF v_start IS NOT NULL THEN
        SELECT COUNT(*) INTO v_ov
          FROM Contests c JOIN CricketMatch m ON m.MatchID = c.MatchID
         WHERE c.ICC_Code = NEW.ICC_Code AND c.MatchID <> NEW.MatchID
           AND m.StartDate <= v_end AND m.EndDate >= v_start;
        IF v_ov > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C9: team already has a match on overlapping dates';
        END IF;
    END IF;
    CALL sp_check_outcome(NEW.MatchID, NEW.ICC_Code, NEW.Outcome);
END$$

CREATE TRIGGER trg_contests_bu BEFORE UPDATE ON Contests FOR EACH ROW
BEGIN
    IF NOT (OLD.Outcome <=> NEW.Outcome) THEN
        CALL sp_check_outcome(NEW.MatchID, NEW.ICC_Code, NEW.Outcome);
    END IF;
END$$

-- C10 line-up rules: player gender = series gender, max 11 per team, one captain
CREATE TRIGGER trg_playsin_bi BEFORE INSERT ON PlaysIn FOR EACH ROW
BEGIN
    DECLARE v_sg VARCHAR(10);
    DECLARE v_pg VARCHAR(10);
    DECLARE v_cnt INT DEFAULT 0;
    SELECT s.Gender INTO v_sg FROM CricketMatch m JOIN Series s ON s.SeriesID = m.SeriesID
     WHERE m.MatchID = NEW.MatchID;
    SELECT Gender INTO v_pg FROM Player WHERE PlayerID = NEW.PlayerID;
    IF v_sg IS NOT NULL AND v_pg IS NOT NULL AND v_sg <> v_pg THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C10: player gender must equal the series gender';
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM PlaysIn WHERE MatchID = NEW.MatchID AND ICC_Code = NEW.ICC_Code;
    IF v_cnt >= 11 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C10: a team has at most 11 players per match';
    END IF;
    IF NEW.IsCaptain THEN
        SELECT COUNT(*) INTO v_cnt FROM PlaysIn
         WHERE MatchID = NEW.MatchID AND ICC_Code = NEW.ICC_Code AND IsCaptain = TRUE;
        IF v_cnt > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C10: a team has exactly one captain per match';
        END IF;
    END IF;
END$$

-- C8 eligibility, C11 snapshots never go back in time
CREATE TRIGGER trg_teamrating_bi BEFORE INSERT ON TeamRating FOR EACH ROW
BEGIN
    DECLARE v_prev DATE;
    IF NOT fn_team_eligible(NEW.ICC_Code, NEW.Format) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C8: team is not eligible for this format';
    END IF;
    SELECT MAX(EffectiveDate) INTO v_prev FROM TeamRating
     WHERE ICC_Code = NEW.ICC_Code AND Format = NEW.Format AND Gender = NEW.Gender;
    IF v_prev IS NOT NULL AND NEW.EffectiveDate < v_prev THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C11: snapshot cannot be dated earlier than the previous snapshot';
    END IF;
END$$

-- C11 weekday, C12 no women Tests, C13 retirement + qualifying window, C14 top-100 cap
CREATE TRIGGER trg_playerrating_bi BEFORE INSERT ON PlayerRating FOR EACH ROW
BEGIN
    DECLARE v_g VARCHAR(10);
    DECLARE v_c INT DEFAULT 0;
    DECLARE v_months INT;
    DECLARE v_max INT;
    SELECT Gender INTO v_g FROM Player WHERE PlayerID = NEW.PlayerID;
    SET v_max = fn_param('MAX_LIST_SIZE');
    IF v_g = 'Men' AND WEEKDAY(NEW.SnapshotDate) <> 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C11: men''s player snapshots fall on a Wednesday';
    END IF;
    IF v_g = 'Women' AND WEEKDAY(NEW.SnapshotDate) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C11: women''s player snapshots fall on a Tuesday';
    END IF;
    IF v_g = 'Women' AND NEW.Format = 'Test' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C12: there are no women''s Test ratings';
    END IF;
    IF fn_player_retired(NEW.PlayerID, NEW.Format) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C13: player has retired from this format';
    END IF;
    IF COALESCE(@bulk_load, 0) = 0 THEN
        SET v_months = fn_param(CONCAT('QUALIFY_MONTHS_', UPPER(NEW.Format)));
        SELECT COUNT(*) INTO v_c
          FROM PlaysIn pi
          JOIN CricketMatch m ON m.MatchID = pi.MatchID
          JOIN Series s ON s.SeriesID = m.SeriesID
         WHERE pi.PlayerID = NEW.PlayerID AND s.Format = NEW.Format
           AND m.EndDate <= NEW.SnapshotDate
           AND m.EndDate > DATE_SUB(NEW.SnapshotDate, INTERVAL v_months MONTH);
        IF v_c = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C13: player has no appearance inside the qualifying window';
        END IF;
    END IF;
    IF NEW.BattingPoints IS NOT NULL THEN
        SELECT COUNT(*) INTO v_c FROM PlayerRating pr JOIN Player p ON p.PlayerID = pr.PlayerID
         WHERE pr.Format = NEW.Format AND pr.SnapshotDate = NEW.SnapshotDate
           AND p.Gender = v_g AND pr.BattingPoints IS NOT NULL;
        IF v_c >= v_max THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C14: batting list already has 100 players for this snapshot';
        END IF;
    END IF;
    IF NEW.BowlingPoints IS NOT NULL THEN
        SELECT COUNT(*) INTO v_c FROM PlayerRating pr JOIN Player p ON p.PlayerID = pr.PlayerID
         WHERE pr.Format = NEW.Format AND pr.SnapshotDate = NEW.SnapshotDate
           AND p.Gender = v_g AND pr.BowlingPoints IS NOT NULL;
        IF v_c >= v_max THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'C14: bowling list already has 100 players for this snapshot';
        END IF;
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. Views for derived attributes (never stored)
-- ---------------------------------------------------------------------
-- Rating = ROUND(Points / Matches); RankPos shares ties (Phase 1 "Position")
CREATE VIEW v_team_rating AS
SELECT tr.ICC_Code, t.TeamName, tr.Format, tr.Gender, tr.EffectiveDate,
       tr.Matches, tr.Points,
       ROUND(tr.Points / tr.Matches) AS Rating,
       RANK() OVER (PARTITION BY tr.Format, tr.Gender, tr.EffectiveDate
                    ORDER BY ROUND(tr.Points / tr.Matches) DESC) AS RankPos
  FROM TeamRating tr
  JOIN Team t ON t.ICC_Code = tr.ICC_Code;

CREATE VIEW v_latest_team_rating AS
SELECT v.*
  FROM v_team_rating v
  JOIN (SELECT Format, Gender, MAX(EffectiveDate) AS LatestDate
          FROM TeamRating GROUP BY Format, Gender) l
    ON l.Format = v.Format AND l.Gender = v.Gender AND l.LatestDate = v.EffectiveDate;

-- AllRounderIndex = BattingPoints x BowlingPoints / 1000; ranks per
-- (Format, SnapshotDate, player gender), NULL when not on that list
CREATE VIEW v_player_rating AS
SELECT pr.PlayerID, p.FirstName, p.LastName, p.Gender, p.ICC_Code, t.TeamName,
       pr.Format, pr.SnapshotDate, pr.BattingPoints, pr.BowlingPoints,
       CASE WHEN pr.BattingPoints IS NOT NULL AND pr.BowlingPoints IS NOT NULL
            THEN ROUND(pr.BattingPoints * pr.BowlingPoints / 1000, 1) END AS AllRounderIndex,
       CASE WHEN pr.BattingPoints IS NOT NULL
            THEN RANK() OVER (PARTITION BY pr.Format, pr.SnapshotDate, p.Gender
                              ORDER BY pr.BattingPoints DESC) END AS BattingRank,
       CASE WHEN pr.BowlingPoints IS NOT NULL
            THEN RANK() OVER (PARTITION BY pr.Format, pr.SnapshotDate, p.Gender
                              ORDER BY pr.BowlingPoints DESC) END AS BowlingRank,
       CASE WHEN pr.BattingPoints IS NOT NULL AND pr.BowlingPoints IS NOT NULL
            THEN RANK() OVER (PARTITION BY pr.Format, pr.SnapshotDate, p.Gender
                              ORDER BY pr.BattingPoints * pr.BowlingPoints DESC) END AS AllRounderRank
  FROM PlayerRating pr
  JOIN Player p ON p.PlayerID = pr.PlayerID
  JOIN Team t   ON t.ICC_Code = p.ICC_Code;

CREATE VIEW v_latest_player_rating AS
SELECT v.*
  FROM v_player_rating v
  JOIN (SELECT pr.Format, p.Gender, MAX(pr.SnapshotDate) AS LatestDate
          FROM PlayerRating pr JOIN Player p ON p.PlayerID = pr.PlayerID
         GROUP BY pr.Format, p.Gender) l
    ON l.Format = v.Format AND l.Gender = v.Gender AND l.LatestDate = v.SnapshotDate;