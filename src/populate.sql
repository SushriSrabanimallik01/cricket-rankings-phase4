-- =====================================================================
-- populate.sql  |  Team 38  |  ICC Cricket Rankings
-- Run AFTER schema.sql:  mysql -u <user> -p < populate.sql
--
-- DATA SOURCES (all retrieved Nov 2026)
--  * Team rating tables: ICC men's Test / ODI / T20I and women's ODI / T20I
--    tables as published on icc-cricket.com and mirrored by Wikipedia
--    (snapshots dated 12 Sep, 31 Oct, 4 Sep, 14 Oct, 31 Aug, 28 Oct 2026) and
--    Wisden's "start of 2026" ICC tables (2 Jan 2026), Cricinfo (1 Nov 2026).
--  * Series / matches: Wikipedia + ESPNcricinfo + news reports for the
--    ICC Men's T20 World Cup 2026, its Asia & EAP Qualifier (Oman, Oct 2025),
--    India tour of Sri Lanka (Tests, Aug 2026), West Indies tour of India
--    (ODIs, Sep-Oct 2026) and the ICC Women's Cricket World Cup 2025 final.
--  * Player ratings: the ICC top-5 batting and bowling tables of 4 Nov 2026
--    (men) and 3 Nov 2026 (women) as published on icc-cricket.com, plus older
--    Test lists: batting 10 Jun 2026 (Wisden), batting mid-Sep 2026 (date
--    inferred), bowling 9 Sep and 28 Oct 2026 (ICC tables as reported).
--    Lists are top-5 (older Test lists are longer), because only published
--    values are stored.
--
-- KNOWN LIMITATIONS (also listed in README):
--  * Carried-forward rows: where a team did not play between two table dates
--    its previous Matches/Points are repeated in the newer snapshot
--    (men's T20I 1 Nov 2026 for teams outside the top 9; women's ODI and
--    T20I 28 Oct 2026 for teams not named in the source).
--  * Positions of lower-ranked teams count only teams stored in this
--    database (e.g. Uganda or Hong Kong are not stored).
--  * Line-ups (PlaysIn) are recorded only for players whose appearance was
--    confirmed; line-ups are optional in the Phase 1 requirements.
--  * @bulk_load = 1 skips only the C13 qualifying-window check and the
--    margin-on-insert check of the triggers (see schema.sql).
-- =====================================================================

USE icc_rankings_db;
SET @bulk_load = 1;

-- ---------------------------------------------------------------------
-- TEAM
-- ---------------------------------------------------------------------
INSERT INTO Team (ICC_Code, TeamName, EligibleFormat1, EligibleFormat2, EligibleFormat3) VALUES
('IND', 'India',                'Test', 'ODI', 'T20I'),
('AUS', 'Australia',            'Test', 'ODI', 'T20I'),
('ENG', 'England',              'Test', 'ODI', 'T20I'),
('SA',  'South Africa',         'Test', 'ODI', 'T20I'),
('NZ',  'New Zealand',          'Test', 'ODI', 'T20I'),
('PAK', 'Pakistan',             'Test', 'ODI', 'T20I'),
('SL',  'Sri Lanka',            'Test', 'ODI', 'T20I'),
('WI',  'West Indies',          'Test', 'ODI', 'T20I'),
('BAN', 'Bangladesh',           'Test', 'ODI', 'T20I'),
('AFG', 'Afghanistan',          'Test', 'ODI', 'T20I'),
('ZIM', 'Zimbabwe',             'Test', 'ODI', 'T20I'),
('IRE', 'Ireland',              'Test', 'ODI', 'T20I'),
('SCO', 'Scotland',             'ODI',  'T20I', NULL),
('NED', 'Netherlands',          'ODI',  'T20I', NULL),
('USA', 'United States',        'ODI',  'T20I', NULL),
('OMA', 'Oman',                 'ODI',  'T20I', NULL),
('NAM', 'Namibia',              'ODI',  'T20I', NULL),
('NEP', 'Nepal',                'ODI',  'T20I', NULL),
('UAE', 'United Arab Emirates', 'ODI',  'T20I', NULL),
('CAN', 'Canada',               'ODI',  'T20I', NULL),
('THA', 'Thailand',             'ODI',  'T20I', NULL),
('PNG', 'Papua New Guinea',     'ODI',  'T20I', NULL),
('ITA', 'Italy',                'T20I', NULL,   NULL),
('SAM', 'Samoa',                'T20I', NULL,   NULL);

-- ---------------------------------------------------------------------
-- VENUE (IDs fixed so later inserts can reference them)
-- ---------------------------------------------------------------------
INSERT INTO Venue (VenueID, VenueName, City, Country) VALUES
(1,  'Wankhede Stadium',                                        'Mumbai',          'India'),
(2,  'Narendra Modi Stadium',                                   'Ahmedabad',       'India'),
(3,  'Arun Jaitley Stadium',                                    'Delhi',           'India'),
(4,  'Eden Gardens',                                            'Kolkata',         'India'),
(5,  'M. A. Chidambaram Stadium',                               'Chennai',         'India'),
(6,  'R. Premadasa Stadium',                                    'Colombo',         'Sri Lanka'),
(7,  'Sinhalese Sports Club Ground',                            'Colombo',         'Sri Lanka'),
(8,  'Pallekele International Cricket Stadium',                 'Kandy',           'Sri Lanka'),
(9,  'Galle International Stadium',                              'Galle',           'Sri Lanka'),
(10, 'Greenfield International Stadium',                        'Thiruvananthapuram', 'India'),
(11, 'Barsapara Cricket Stadium',                               'Guwahati',        'India'),
(12, 'Maharaja Yadavindra Singh International Cricket Stadium', 'Mullanpur',       'India'),
(13, 'Oman Cricket Academy Ground (Ministry Turf 1)',           'Al Amerat',       'Oman'),
(14, 'DY Patil Stadium',                                        'Navi Mumbai',     'India');

-- ---------------------------------------------------------------------
-- SERIES (main event first, so the qualifier can reference it: C15)
-- ---------------------------------------------------------------------
INSERT INTO Series (SeriesID, SeriesName, SeriesType, Gender, Format, StartDate, EndDate, MainEventID) VALUES
(1, 'ICC Men''s T20 World Cup 2026',                     'ICC Event', 'Men',   'T20I', '2026-02-07', '2026-03-08', NULL),
(2, 'ICC Men''s T20 World Cup Asia & EAP Qualifier 2025','Qualifier', 'Men',   'T20I', '2025-10-08', '2025-10-17', 1),
(3, 'India tour of Sri Lanka 2026 (Tests)',              'Bilateral', 'Men',   'Test', '2026-08-15', '2026-08-27', NULL),
(4, 'West Indies tour of India 2026 (ODIs)',             'Bilateral', 'Men',   'ODI',  '2026-09-27', '2026-10-03', NULL),
(5, 'ICC Women''s Cricket World Cup 2025',               'ICC Event', 'Women', 'ODI',  '2025-09-30', '2025-11-02', NULL);

-- ---------------------------------------------------------------------
-- CRICKETMATCH (margin only where the source states it)
-- ---------------------------------------------------------------------
INSERT INTO CricketMatch (MatchID, StartDate, EndDate, MarginValue, MarginType, VenueID, SeriesID) VALUES
-- ICC Men's T20 World Cup 2026
(1,  '2026-02-07', '2026-02-07',   3, 'Wickets', 7,  1),   -- NED v PAK, SSC Colombo
(2,  '2026-02-07', '2026-02-07',  29, 'Runs',    1,  1),   -- IND v USA, Wankhede
(3,  '2026-02-12', '2026-02-12',  93, 'Runs',    3,  1),   -- IND v NAM, Delhi
(4,  '2026-02-15', '2026-02-15',  61, 'Runs',    6,  1),   -- IND v PAK, R. Premadasa
(5,  '2026-02-18', '2026-02-18',  17, 'Runs',    2,  1),   -- IND v NED, Ahmedabad
(6,  '2026-03-04', '2026-03-04',   9, 'Wickets', 4,  1),   -- Semi-final 1: SA v NZ, Eden Gardens
(7,  '2026-03-05', '2026-03-05', NULL, NULL,     1,  1),   -- Semi-final 2: IND v ENG, Wankhede
(8,  '2026-03-08', '2026-03-08',  96, 'Runs',    2,  1),   -- Final: IND v NZ, Ahmedabad
-- Asia & EAP Qualifier (Oman)
(9,  '2025-10-08', '2025-10-08',   5, 'Wickets', 13, 2),   -- OMA v SAM
(10, '2025-10-12', '2025-10-12', NULL, NULL,     13, 2),   -- UAE v NEP (Super Six)
(11, '2025-10-15', '2025-10-15',  77, 'Runs',    13, 2),   -- UAE v SAM (Super Six)
-- India tour of Sri Lanka, Tests
(12, '2026-08-15', '2026-08-19', 165, 'Runs',    9,  3),   -- 1st Test, Galle
(13, '2026-08-23', '2026-08-27', NULL, NULL,     7,  3),   -- 2nd Test, SSC (drawn)
-- West Indies tour of India, ODIs
(14, '2026-09-27', '2026-09-27',   8, 'Wickets', 10, 4),   -- 1st ODI, Thiruvananthapuram
(15, '2026-09-30', '2026-09-30',   8, 'Wickets', 11, 4),   -- 2nd ODI, Guwahati
(16, '2026-10-03', '2026-10-03', NULL, NULL,     12, 4),   -- 3rd ODI, Mullanpur (WI won)
-- ICC Women's Cricket World Cup 2025 final
(17, '2025-11-02', '2025-11-02',  52, 'Runs',    14, 5);   -- IND v SA, Navi Mumbai

INSERT INTO TestMatch (MatchID, ScheduledDays) VALUES (12, 5), (13, 5);

INSERT INTO LimitedOversMatch (MatchID, OversPerSide, DLSApplied) VALUES
(1, 20, FALSE), (2, 20, FALSE), (3, 20, FALSE), (4, 20, FALSE), (5, 20, FALSE),
(6, 20, FALSE), (7, 20, FALSE), (8, 20, FALSE),
(9, 20, FALSE), (10, 20, FALSE), (11, 20, FALSE),
(14, 50, FALSE), (15, 50, FALSE), (16, 50, FALSE),
(17, 50, FALSE);

-- ---------------------------------------------------------------------
-- CONTESTS (winner row first, then loser row: complementary outcomes, C7)
-- ---------------------------------------------------------------------
INSERT INTO Contests (MatchID, ICC_Code, Outcome) VALUES
(1,  'PAK', 'Win'),  (1,  'NED', 'Loss'),
(2,  'IND', 'Win'),  (2,  'USA', 'Loss'),
(3,  'IND', 'Win'),  (3,  'NAM', 'Loss'),
(4,  'IND', 'Win'),  (4,  'PAK', 'Loss'),
(5,  'IND', 'Win'),  (5,  'NED', 'Loss'),
(6,  'NZ',  'Win'),  (6,  'SA',  'Loss'),
(7,  'IND', 'Win'),  (7,  'ENG', 'Loss'),
(8,  'IND', 'Win'),  (8,  'NZ',  'Loss'),
(9,  'OMA', 'Win'),  (9,  'SAM', 'Loss'),
(10, 'NEP', 'Win'),  (10, 'UAE', 'Loss'),
(11, 'UAE', 'Win'),  (11, 'SAM', 'Loss'),
(12, 'IND', 'Win'),  (12, 'SL',  'Loss'),
(13, 'IND', 'Draw'), (13, 'SL',  'Draw'),
(14, 'IND', 'Win'),  (14, 'WI',  'Loss'),
(15, 'IND', 'Win'),  (15, 'WI',  'Loss'),
(16, 'WI',  'Win'),  (16, 'IND', 'Loss'),
(17, 'IND', 'Win'),  (17, 'SA',  'Loss');

-- ---------------------------------------------------------------------
-- PLAYER  (DOBs from public records; current team in ICC_Code)
-- RetiredFormat columns: Kohli and Rohit retired from Tests and T20Is,
-- Jadeja from T20Is.
-- ---------------------------------------------------------------------
INSERT INTO Player (PlayerID, FirstName, LastName, DateOfBirth, Gender, RetiredFormat1, RetiredFormat2, RetiredFormat3, ICC_Code) VALUES
-- India (men)
(1,  'Shubman',     'Gill',             '1999-09-08', 'Men', NULL,   NULL,   NULL, 'IND'),
(2,  'Virat',       'Kohli',            '1988-11-05', 'Men', 'Test', 'T20I', NULL, 'IND'),
(3,  'Rohit',       'Sharma',           '1987-04-30', 'Men', 'Test', 'T20I', NULL, 'IND'),
(4,  'Jasprit',     'Bumrah',           '1993-12-06', 'Men', NULL,   NULL,   NULL, 'IND'),
(5,  'Kuldeep',     'Yadav',            '1994-12-14', 'Men', NULL,   NULL,   NULL, 'IND'),
(6,  'Ravindra',    'Jadeja',           '1988-12-06', 'Men', 'T20I', NULL,   NULL, 'IND'),
(7,  'Yashasvi',    'Jaiswal',          '2001-12-28', 'Men', NULL,   NULL,   NULL, 'IND'),
(8,  'Rishabh',     'Pant',             '1997-10-04', 'Men', NULL,   NULL,   NULL, 'IND'),
(9,  'KL',          'Rahul',            '1992-04-18', 'Men', NULL,   NULL,   NULL, 'IND'),
(10, 'Suryakumar',  'Yadav',            '1990-09-14', 'Men', NULL,   NULL,   NULL, 'IND'),
(11, 'Hardik',      'Pandya',           '1993-10-11', 'Men', NULL,   NULL,   NULL, 'IND'),
(12, 'Sanju',       'Samson',           '1994-11-11', 'Men', NULL,   NULL,   NULL, 'IND'),
(13, 'Ishan',       'Kishan',           '1998-07-18', 'Men', NULL,   NULL,   NULL, 'IND'),
(14, 'Varun',       'Chakravarthy',     '1991-08-29', 'Men', NULL,   NULL,   NULL, 'IND'),
(15, 'Abhishek',    'Sharma',           '2000-09-04', 'Men', NULL,   NULL,   NULL, 'IND'),
(16, 'Prasidh',     'Krishna',          '1996-02-19', 'Men', NULL,   NULL,   NULL, 'IND'),
(17, 'Devdutt',     'Padikkal',         '2000-07-07', 'Men', NULL,   NULL,   NULL, 'IND'),
(18, 'Nitish Kumar','Reddy',            '2003-05-26', 'Men', NULL,   NULL,   NULL, 'IND'),
(19, 'Shreyas',     'Iyer',             '1994-12-06', 'Men', NULL,   NULL,   NULL, 'IND'),
-- England (men)
(21, 'Joe',         'Root',             '1990-12-30', 'Men', NULL, NULL, NULL, 'ENG'),
(22, 'Harry',       'Brook',            '1999-02-22', 'Men', NULL, NULL, NULL, 'ENG'),
(23, 'Ben',         'Stokes',           '1991-06-04', 'Men', NULL, NULL, NULL, 'ENG'),
(24, 'Jos',         'Buttler',          '1990-09-08', 'Men', NULL, NULL, NULL, 'ENG'),
(25, 'Jofra',       'Archer',           '1995-04-01', 'Men', NULL, NULL, NULL, 'ENG'),
(26, 'Adil',        'Rashid',           '1988-02-17', 'Men', NULL, NULL, NULL, 'ENG'),
(27, 'Will',        'Jacks',            '1998-11-21', 'Men', NULL, NULL, NULL, 'ENG'),
(28, 'Phil',        'Salt',             '1996-08-28', 'Men', NULL, NULL, NULL, 'ENG'),
(29, 'Ollie',       'Robinson',         '1998-12-01', 'Men', NULL, NULL, NULL, 'ENG'),
(30, 'Ben',         'Duckett',          '1994-10-17', 'Men', NULL, NULL, NULL, 'ENG'),
(31, 'Jamie',       'Smith',            '2000-07-12', 'Men', NULL, NULL, NULL, 'ENG'),
(32, 'Gus',         'Atkinson',         '1998-01-19', 'Men', NULL, NULL, NULL, 'ENG'),
-- Australia (men)
(41, 'Steve',       'Smith',            '1989-06-02', 'Men', NULL, NULL, NULL, 'AUS'),
(42, 'Travis',      'Head',             '1993-12-29', 'Men', NULL, NULL, NULL, 'AUS'),
(43, 'Pat',         'Cummins',          '1993-05-08', 'Men', NULL, NULL, NULL, 'AUS'),
(44, 'Mitchell',    'Starc',            '1990-01-30', 'Men', NULL, NULL, NULL, 'AUS'),
(45, 'Josh',        'Hazlewood',        '1991-01-08', 'Men', NULL, NULL, NULL, 'AUS'),
(46, 'Scott',       'Boland',           '1989-04-11', 'Men', NULL, NULL, NULL, 'AUS'),
(47, 'Nathan',      'Lyon',             '1987-11-20', 'Men', NULL, NULL, NULL, 'AUS'),
(48, 'Cameron',     'Green',            '1999-06-03', 'Men', NULL, NULL, NULL, 'AUS'),
(49, 'Alex',        'Carey',            '1991-08-27', 'Men', NULL, NULL, NULL, 'AUS'),
(50, 'Glenn',       'Maxwell',          '1988-10-14', 'Men', NULL, NULL, NULL, 'AUS'),
(51, 'Adam',        'Zampa',            '1992-03-31', 'Men', NULL, NULL, NULL, 'AUS'),
-- South Africa (men)
(61, 'Temba',       'Bavuma',           '1990-05-17', 'Men', NULL, NULL, NULL, 'SA'),
(62, 'Aiden',       'Markram',          '1994-10-04', 'Men', NULL, NULL, NULL, 'SA'),
(63, 'Marco',       'Jansen',           '2000-05-01', 'Men', NULL, NULL, NULL, 'SA'),
(64, 'Kagiso',      'Rabada',           '1995-05-25', 'Men', NULL, NULL, NULL, 'SA'),
(65, 'Keshav',      'Maharaj',          '1990-02-07', 'Men', NULL, NULL, NULL, 'SA'),
(66, 'Lungi',       'Ngidi',            '1996-03-29', 'Men', NULL, NULL, NULL, 'SA'),
(67, 'Quinton',     'de Kock',          '1992-12-17', 'Men', NULL, NULL, NULL, 'SA'),
(68, 'Simon',       'Harmer',           '1989-02-10', 'Men', NULL, NULL, NULL, 'SA'),
(69, 'Wiaan',       'Mulder',           '1998-02-19', 'Men', NULL, NULL, NULL, 'SA'),
-- New Zealand (men)
(81, 'Kane',        'Williamson',       '1990-08-08', 'Men', NULL, NULL, NULL, 'NZ'),
(82, 'Daryl',       'Mitchell',         '1991-05-20', 'Men', NULL, NULL, NULL, 'NZ'),
(83, 'Matt',        'Henry',            '1991-12-14', 'Men', NULL, NULL, NULL, 'NZ'),
(84, 'Rachin',      'Ravindra',         '1999-11-18', 'Men', NULL, NULL, NULL, 'NZ'),
(85, 'Devon',       'Conway',           '1991-07-08', 'Men', NULL, NULL, NULL, 'NZ'),
(86, 'Finn',        'Allen',            '1999-04-22', 'Men', NULL, NULL, NULL, 'NZ'),
(87, 'Tim',         'Seifert',          '1994-12-14', 'Men', NULL, NULL, NULL, 'NZ'),
(88, 'Mitchell',    'Santner',          '1992-02-05', 'Men', NULL, NULL, NULL, 'NZ'),
-- Pakistan (men)
(101,'Babar',       'Azam',             '1994-10-15', 'Men', NULL, NULL, NULL, 'PAK'),
(102,'Shaheen Shah','Afridi',           '2000-04-06', 'Men', NULL, NULL, NULL, 'PAK'),
(103,'Saud',        'Shakeel',          '1995-09-05', 'Men', NULL, NULL, NULL, 'PAK'),
(104,'Noman',       'Ali',              '1986-08-06', 'Men', NULL, NULL, NULL, 'PAK'),
(105,'Salman Ali',  'Agha',             '1993-11-23', 'Men', NULL, NULL, NULL, 'PAK'),
(106,'Fakhar',      'Zaman',            '1990-04-10', 'Men', NULL, NULL, NULL, 'PAK'),
-- Sri Lanka (men)
(121,'Kamindu',     'Mendis',           '1998-09-30', 'Men', NULL, NULL, NULL, 'SL'),
(122,'Pathum',      'Nissanka',         '1998-05-18', 'Men', NULL, NULL, NULL, 'SL'),
(123,'Dinesh',      'Chandimal',        '1989-11-18', 'Men', NULL, NULL, NULL, 'SL'),
(124,'Maheesh',     'Theekshana',       '2000-08-01', 'Men', NULL, NULL, NULL, 'SL'),
(125,'Wanindu',     'Hasaranga',        '1997-07-29', 'Men', NULL, NULL, NULL, 'SL'),
(126,'Dasun',       'Shanaka',          '1991-09-09', 'Men', NULL, NULL, NULL, 'SL'),
(127,'Dhananjaya',  'de Silva',         '1991-09-06', 'Men', NULL, NULL, NULL, 'SL'),
(128,'Angelo',      'Mathews',          '1987-06-02', 'Men', NULL, NULL, NULL, 'SL'),
-- West Indies (men)
(141,'Shai',        'Hope',             '1993-11-10', 'Men', NULL, NULL, NULL, 'WI'),
(142,'Roston',      'Chase',            '1992-03-22', 'Men', NULL, NULL, NULL, 'WI'),
(143,'Jason',       'Holder',           '1991-11-05', 'Men', NULL, NULL, NULL, 'WI'),
(144,'Alzarri',     'Joseph',           '1996-11-11', 'Men', NULL, NULL, NULL, 'WI'),
(145,'Shamar',      'Joseph',           '1999-08-31', 'Men', NULL, NULL, NULL, 'WI'),
(146,'Akeal',       'Hosein',           '1993-04-16', 'Men', NULL, NULL, NULL, 'WI'),
(147,'Shimron',     'Hetmyer',          '1996-12-26', 'Men', NULL, NULL, NULL, 'WI'),
(148,'Romario',     'Shepherd',         '1994-11-26', 'Men', NULL, NULL, NULL, 'WI'),
-- Afghanistan (men)
(161,'Rashid',      'Khan',             '1998-09-20', 'Men', NULL, NULL, NULL, 'AFG'),
(162,'Ibrahim',     'Zadran',           '2001-12-12', 'Men', NULL, NULL, NULL, 'AFG'),
(163,'Rahmanullah', 'Gurbaz',           '2001-11-28', 'Men', NULL, NULL, NULL, 'AFG'),
(164,'Azmatullah',  'Omarzai',          '2000-03-24', 'Men', NULL, NULL, NULL, 'AFG'),
(165,'Mohammad',    'Nabi',             '1985-01-01', 'Men', NULL, NULL, NULL, 'AFG'),
(166,'Rahmat',      'Shah',             '1993-07-06', 'Men', NULL, NULL, NULL, 'AFG'),
-- Bangladesh, Zimbabwe, USA (men)
(181,'Mushfiqur',   'Rahim',            '1987-06-09', 'Men', NULL, NULL, NULL, 'BAN'),
(182,'Najmul Hossain','Shanto',         '1998-08-25', 'Men', NULL, NULL, NULL, 'BAN'),
(183,'Mustafizur',  'Rahman',           '1995-09-06', 'Men', NULL, NULL, NULL, 'BAN'),
(184,'Litton',      'Das',              '1994-10-13', 'Men', NULL, NULL, NULL, 'BAN'),
(191,'Sikandar',    'Raza',             '1986-04-24', 'Men', NULL, NULL, NULL, 'ZIM'),
(192,'Sean',        'Williams',         '1986-09-26', 'Men', NULL, NULL, NULL, 'ZIM'),
(193,'Blessing',    'Muzarabani',       '1996-10-02', 'Men', NULL, NULL, NULL, 'ZIM'),
(201,'Saurabh',     'Netravalkar',      '1991-10-16', 'Men', NULL, NULL, NULL, 'USA'),
(202,'Monank',      'Patel',            '1993-05-01', 'Men', NULL, NULL, NULL, 'USA'),
-- Women
(301,'Harmanpreet', 'Kaur',             '1989-03-08', 'Women', NULL, NULL, NULL, 'IND'),
(302,'Smriti',      'Mandhana',         '1996-07-18', 'Women', NULL, NULL, NULL, 'IND'),
(303,'Shafali',     'Verma',            '2004-01-28', 'Women', NULL, NULL, NULL, 'IND'),
(304,'Deepti',      'Sharma',           '1997-08-24', 'Women', NULL, NULL, NULL, 'IND'),
(311,'Laura',       'Wolvaardt',        '1999-04-26', 'Women', NULL, NULL, NULL, 'SA'),
(312,'Marizanne',   'Kapp',             '1989-01-04', 'Women', NULL, NULL, NULL, 'SA'),
(321,'Ellyse',      'Perry',            '1990-11-03', 'Women', NULL, NULL, NULL, 'AUS'),
(322,'Alyssa',      'Healy',            '1990-03-24', 'Women', NULL, NULL, NULL, 'AUS'),
(323,'Ashleigh',    'Gardner',          '1997-04-15', 'Women', NULL, NULL, NULL, 'AUS'),
(331,'Nat',         'Sciver-Brunt',     '1992-08-20', 'Women', NULL, NULL, NULL, 'ENG'),
(332,'Sophie',      'Ecclestone',       '1999-05-06', 'Women', NULL, NULL, NULL, 'ENG'),
(341,'Amelia',      'Kerr',             '2000-10-13', 'Women', NULL, NULL, NULL, 'NZ');


-- Players added from the ICC rankings pages (top-5 lists, Nov 2026)
INSERT INTO Player (PlayerID, FirstName, LastName, DateOfBirth, Gender, RetiredFormat1, RetiredFormat2, RetiredFormat3, ICC_Code) VALUES
(107,'Abrar',      'Ahmed',       '1998-08-11', 'Men',   NULL, NULL, NULL, 'PAK'),
(108,'Sahibzada',  'Farhan',      '1996-03-06', 'Men',   NULL, NULL, NULL, 'PAK'),
(305,'Sree',       'Charani',     '2004-08-04', 'Women', NULL, NULL, NULL, 'IND'),
(324,'Beth',       'Mooney',      '1994-01-14', 'Women', NULL, NULL, NULL, 'AUS'),
(325,'Phoebe',     'Litchfield',  '2003-04-18', 'Women', NULL, NULL, NULL, 'AUS'),
(326,'Georgia',    'Voll',        '2003-05-19', 'Women', NULL, NULL, NULL, 'AUS'),
(327,'Alana',      'King',        '1995-11-29', 'Women', NULL, NULL, NULL, 'AUS'),
(328,'Megan',      'Schutt',      '1993-01-15', 'Women', NULL, NULL, NULL, 'AUS'),
(329,'Annabel',    'Sutherland',  '2001-10-12', 'Women', NULL, NULL, NULL, 'AUS'),
(333,'Charlie',    'Dean',        '2000-12-22', 'Women', NULL, NULL, NULL, 'ENG'),
(334,'Lauren',     'Bell',        '2001-01-02', 'Women', NULL, NULL, NULL, 'ENG'),
(351,'Hayley',     'Matthews',    '1998-03-19', 'Women', NULL, NULL, NULL, 'WI');

-- ---------------------------------------------------------------------
-- PLAYSIN: only appearances confirmed by match reports (line-ups optional)
-- ---------------------------------------------------------------------
INSERT INTO PlaysIn (PlayerID, MatchID, ICC_Code, IsCaptain) VALUES
-- T20 World Cup 2026
(10, 2, 'IND', TRUE),  (201, 2, 'USA', FALSE),
(13, 3, 'IND', FALSE),
(10, 4, 'IND', TRUE),  (105, 4, 'PAK', TRUE),
(86, 6, 'NZ',  FALSE), (62,  6, 'SA',  TRUE),
-- India tour of Sri Lanka (Tests)
(1,  12, 'IND', TRUE), (17, 12, 'IND', FALSE),
(1,  13, 'IND', TRUE), (7,  13, 'IND', FALSE),
-- West Indies tour of India (ODIs)
(1,  14, 'IND', TRUE), (2,  14, 'IND', FALSE), (3,  14, 'IND', FALSE),
(5,  14, 'IND', FALSE),(16, 14, 'IND', FALSE), (18, 14, 'IND', FALSE),
(142,14, 'WI',  FALSE),(144,14, 'WI',  FALSE),
(1,  15, 'IND', TRUE), (2,  15, 'IND', FALSE), (3,  15, 'IND', FALSE),
(5,  15, 'IND', FALSE),(141,15, 'WI',  TRUE),  (145,15, 'WI',  FALSE),
(1,  16, 'IND', TRUE),
-- Women's World Cup 2025 final
(301,17, 'IND', TRUE), (302,17, 'IND', FALSE), (303,17, 'IND', FALSE),
(304,17, 'IND', FALSE),(311,17, 'SA',  TRUE);

-- ---------------------------------------------------------------------
-- TEAMRATING: each (team, format, gender) is inserted oldest date first (C11)
-- ---------------------------------------------------------------------
-- Men's Test, 2 Jan 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('AUS','Test','Men','2026-01-02',30,3732),('SA','Test','Men','2026-01-02',31,3581),
('ENG','Test','Men','2026-01-02',40,4469),('IND','Test','Men','2026-01-02',39,4064),
('NZ','Test','Men','2026-01-02',29,2839),('SL','Test','Men','2026-01-02',27,2364),
('PAK','Test','Men','2026-01-02',25,2050),('WI','Test','Men','2026-01-02',33,2270),
('BAN','Test','Men','2026-01-02',30,1888),('IRE','Test','Men','2026-01-02',8,185),
('ZIM','Test','Men','2026-01-02',18,208),('AFG','Test','Men','2026-01-02',6,62);
-- Men's Test, 12 Sep 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('AUS','Test','Men','2026-09-12',27,3411),('SA','Test','Men','2026-09-12',19,2256),
('NZ','Test','Men','2026-09-12',22,2326),('IND','Test','Men','2026-09-12',29,3042),
('ENG','Test','Men','2026-09-12',36,3658),('BAN','Test','Men','2026-09-12',24,1878),
('SL','Test','Men','2026-09-12',19,1434),('WI','Test','Men','2026-09-12',27,2008),
('PAK','Test','Men','2026-09-12',23,1623),('ZIM','Test','Men','2026-09-12',13,217);
-- Men's Test, 31 Oct 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('SA','Test','Men','2026-10-31',23,2860),('AUS','Test','Men','2026-10-31',31,3787),
('NZ','Test','Men','2026-10-31',22,2336),('IND','Test','Men','2026-10-31',29,3042),
('ENG','Test','Men','2026-10-31',36,3658),('BAN','Test','Men','2026-10-31',25,1916),
('SL','Test','Men','2026-10-31',19,1434),('WI','Test','Men','2026-10-31',27,2008),
('PAK','Test','Men','2026-10-31',23,1623),('ZIM','Test','Men','2026-10-31',13,217);

-- Men's ODI, 2 Jan 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('IND','ODI','Men','2026-01-02',42,5089),('NZ','ODI','Men','2026-01-02',44,4956),
('AUS','ODI','Men','2026-01-02',38,4134),('PAK','ODI','Men','2026-01-02',41,4294),
('SL','ODI','Men','2026-01-02',44,4392),('SA','ODI','Men','2026-01-02',41,4022),
('AFG','ODI','Men','2026-01-02',28,2657),('ENG','ODI','Men','2026-01-02',40,3432),
('WI','ODI','Men','2026-01-02',41,3173),('BAN','ODI','Men','2026-01-02',38,2882),
('ZIM','ODI','Men','2026-01-02',24,1291),('IRE','ODI','Men','2026-01-02',18,938),
('SCO','ODI','Men','2026-01-02',33,1522),('USA','ODI','Men','2026-01-02',38,1668),
('NED','ODI','Men','2026-01-02',36,1425),('OMA','ODI','Men','2026-01-02',25,886),
('NEP','ODI','Men','2026-01-02',36,959),('NAM','ODI','Men','2026-01-02',33,707),
('CAN','ODI','Men','2026-01-02',23,357),('UAE','ODI','Men','2026-01-02',36,396);
-- Men's ODI, 4 Sep 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('IND','ODI','Men','2026-09-04',33,3841),('NZ','ODI','Men','2026-09-04',35,3809),
('AUS','ODI','Men','2026-09-04',29,2965),('SA','ODI','Men','2026-09-04',28,2855),
('PAK','ODI','Men','2026-09-04',32,3215),('SL','ODI','Men','2026-09-04',36,3470),
('ENG','ODI','Men','2026-09-04',31,2898),('AFG','ODI','Men','2026-09-04',28,2565),
('BAN','ODI','Men','2026-09-04',39,3251),('WI','ODI','Men','2026-09-04',34,2624),
('ZIM','ODI','Men','2026-09-04',15,941),('IRE','ODI','Men','2026-09-04',16,815),
('SCO','ODI','Men','2026-09-04',27,1200),('NED','ODI','Men','2026-09-04',30,1309),
('USA','ODI','Men','2026-09-04',26,1035),('OMA','ODI','Men','2026-09-04',22,716),
('NAM','ODI','Men','2026-09-04',20,623),('NEP','ODI','Men','2026-09-04',31,790),
('UAE','ODI','Men','2026-09-04',25,413),('CAN','ODI','Men','2026-09-04',21,200);

-- Men's T20I, 2 Jan 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('IND','T20I','Men','2026-01-02',71,19312),('AUS','T20I','Men','2026-01-02',42,11199),
('ENG','T20I','Men','2026-01-02',45,11609),('NZ','T20I','Men','2026-01-02',53,13318),
('SA','T20I','Men','2026-01-02',53,12739),('WI','T20I','Men','2026-01-02',61,14424),
('PAK','T20I','Men','2026-01-02',73,17149),('SL','T20I','Men','2026-01-02',48,10951),
('BAN','T20I','Men','2026-01-02',67,14925),('AFG','T20I','Men','2026-01-02',45,9895),
('IRE','T20I','Men','2026-01-02',37,7438),('ZIM','T20I','Men','2026-01-02',66,13190),
('NED','T20I','Men','2026-01-02',35,6366),('SCO','T20I','Men','2026-01-02',23,4178),
('NAM','T20I','Men','2026-01-02',35,6344),('UAE','T20I','Men','2026-01-02',60,10584),
('NEP','T20I','Men','2026-01-02',42,7384),('USA','T20I','Men','2026-01-02',33,5769),
('CAN','T20I','Men','2026-01-02',35,5374),('OMA','T20I','Men','2026-01-02',47,7140);
-- Men's T20I, 14 Oct 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('ENG','T20I','Men','2026-10-14',41,11021),('IND','T20I','Men','2026-10-14',71,18987),
('AUS','T20I','Men','2026-10-14',38,9868),('NZ','T20I','Men','2026-10-14',50,12348),
('SA','T20I','Men','2026-10-14',53,12881),('PAK','T20I','Men','2026-10-14',62,14883),
('WI','T20I','Men','2026-10-14',60,14155),('BAN','T20I','Men','2026-10-14',55,12220),
('SL','T20I','Men','2026-10-14',52,11489),('AFG','T20I','Men','2026-10-14',41,8925),
('IRE','T20I','Men','2026-10-14',29,5942),('ZIM','T20I','Men','2026-10-14',59,11911),
('USA','T20I','Men','2026-10-14',20,3650),('NEP','T20I','Men','2026-10-14',44,7968),
('NED','T20I','Men','2026-10-14',24,4311),('NAM','T20I','Men','2026-10-14',41,7358),
('SCO','T20I','Men','2026-10-14',23,4116),('UAE','T20I','Men','2026-10-14',57,9961),
('OMA','T20I','Men','2026-10-14',44,6698),('CAN','T20I','Men','2026-10-14',26,3864),
('ITA','T20I','Men','2026-10-14',15,1988),('SAM','T20I','Men','2026-10-14',21,933);
-- Men's T20I, 1 Nov 2026 (top nine as published; others carried forward)
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('ENG','T20I','Men','2026-11-01',41,11021),('IND','T20I','Men','2026-11-01',76,20268),
('AUS','T20I','Men','2026-11-01',38,9868),('NZ','T20I','Men','2026-11-01',55,13638),
('SA','T20I','Men','2026-11-01',53,12881),('PAK','T20I','Men','2026-11-01',62,14883),
('WI','T20I','Men','2026-11-01',60,14155),('BAN','T20I','Men','2026-11-01',55,12220),
('SL','T20I','Men','2026-11-01',52,11489),('AFG','T20I','Men','2026-11-01',41,8925),
('IRE','T20I','Men','2026-11-01',29,5942),('ZIM','T20I','Men','2026-11-01',59,11911),
('USA','T20I','Men','2026-11-01',20,3650),('NEP','T20I','Men','2026-11-01',44,7968),
('NED','T20I','Men','2026-11-01',24,4311),('NAM','T20I','Men','2026-11-01',41,7358),
('SCO','T20I','Men','2026-11-01',23,4116),('UAE','T20I','Men','2026-11-01',57,9961),
('OMA','T20I','Men','2026-11-01',44,6698),('CAN','T20I','Men','2026-11-01',26,3864),
('ITA','T20I','Men','2026-11-01',15,1988),('SAM','T20I','Men','2026-11-01',21,933);

-- Women's ODI, 31 Aug 2026
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('AUS','ODI','Women','2026-08-31',28,4565),('ENG','ODI','Women','2026-08-31',26,3247),
('IND','ODI','Women','2026-08-31',30,3712),('SA','ODI','Women','2026-08-31',36,3614),
('NZ','ODI','Women','2026-08-31',24,2312),('SL','ODI','Women','2026-08-31',24,2133),
('WI','ODI','Women','2026-08-31',26,1934),('BAN','ODI','Women','2026-08-31',21,1537),
('PAK','ODI','Women','2026-08-31',26,1902),('IRE','ODI','Women','2026-08-31',22,1013),
('SCO','ODI','Women','2026-08-31',9,393),('NED','ODI','Women','2026-08-31',5,208),
('THA','ODI','Women','2026-08-31',7,248),('ZIM','ODI','Women','2026-08-31',19,226),
('UAE','ODI','Women','2026-08-31',8,81),('PNG','ODI','Women','2026-08-31',12,37);
-- Women's ODI, 28 Oct 2026 (AUS, ENG, IND, ZIM updated; others carried forward)
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('AUS','ODI','Women','2026-10-28',31,5085),('ENG','ODI','Women','2026-10-28',29,3653),
('IND','ODI','Women','2026-10-28',33,4114),('SA','ODI','Women','2026-10-28',36,3614),
('NZ','ODI','Women','2026-10-28',24,2312),('SL','ODI','Women','2026-10-28',24,2133),
('WI','ODI','Women','2026-10-28',26,1934),('BAN','ODI','Women','2026-10-28',21,1537),
('PAK','ODI','Women','2026-10-28',26,1902),('IRE','ODI','Women','2026-10-28',22,1013),
('SCO','ODI','Women','2026-10-28',9,393),('NED','ODI','Women','2026-10-28',5,208),
('THA','ODI','Women','2026-10-28',7,248),('ZIM','ODI','Women','2026-10-28',25,349),
('UAE','ODI','Women','2026-10-28',8,81),('PNG','ODI','Women','2026-10-28',12,37);

-- Women's T20I, 31 Aug 2026 (stored teams only)
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('AUS','T20I','Women','2026-08-31',28,8151),('ENG','T20I','Women','2026-08-31',38,10504),
('IND','T20I','Women','2026-08-31',42,11015),('NZ','T20I','Women','2026-08-31',32,7966),
('SA','T20I','Women','2026-08-31',38,9310),('WI','T20I','Women','2026-08-31',33,7829),
('SL','T20I','Women','2026-08-31',38,9010),('PAK','T20I','Women','2026-08-31',34,7189),
('IRE','T20I','Women','2026-08-31',42,8520),('BAN','T20I','Women','2026-08-31',38,7446),
('SCO','T20I','Women','2026-08-31',38,6373),('THA','T20I','Women','2026-08-31',63,9674),
('PNG','T20I','Women','2026-08-31',32,4542),('NED','T20I','Women','2026-08-31',49,6855),
('UAE','T20I','Women','2026-08-31',47,6430),('ZIM','T20I','Women','2026-08-31',35,4285),
('NAM','T20I','Women','2026-08-31',46,5043),('USA','T20I','Women','2026-08-31',28,2741),
('NEP','T20I','Women','2026-08-31',51,4673),('ITA','T20I','Women','2026-08-31',31,2603),
('SAM','T20I','Women','2026-08-31',16,472),('OMA','T20I','Women','2026-08-31',34,1708),
('CAN','T20I','Women','2026-08-31',20,841);
-- Women's T20I, 28 Oct 2026 (top five as published; others carried forward)
INSERT INTO TeamRating (ICC_Code, Format, Gender, EffectiveDate, Matches, Points) VALUES
('AUS','T20I','Women','2026-10-28',30,8753),('ENG','T20I','Women','2026-10-28',38,10504),
('IND','T20I','Women','2026-10-28',52,13779),('NZ','T20I','Women','2026-10-28',34,8444),
('SA','T20I','Women','2026-10-28',43,10588),('WI','T20I','Women','2026-10-28',33,7829),
('SL','T20I','Women','2026-10-28',38,9010),('PAK','T20I','Women','2026-10-28',34,7189),
('IRE','T20I','Women','2026-10-28',42,8520),('BAN','T20I','Women','2026-10-28',38,7446),
('SCO','T20I','Women','2026-10-28',38,6373),('THA','T20I','Women','2026-10-28',63,9674),
('PNG','T20I','Women','2026-10-28',32,4542),('NED','T20I','Women','2026-10-28',49,6855),
('UAE','T20I','Women','2026-10-28',47,6430),('ZIM','T20I','Women','2026-10-28',35,4285),
('NAM','T20I','Women','2026-10-28',46,5043),('USA','T20I','Women','2026-10-28',28,2741),
('NEP','T20I','Women','2026-10-28',51,4673),('ITA','T20I','Women','2026-10-28',31,2603),
('SAM','T20I','Women','2026-10-28',16,472),('OMA','T20I','Women','2026-10-28',34,1708),
('CAN','T20I','Women','2026-10-28',20,841);

-- ---------------------------------------------------------------------
-- PLAYERRATING (men: Wednesdays). BattingPoints / BowlingPoints are only
-- filled where the list was published for that player.
-- ---------------------------------------------------------------------
-- Test batting, Wed 10 Jun 2026
INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) VALUES
(22,'Test','2026-06-10',869,NULL),(42,'Test','2026-06-10',853,NULL),
(21,'Test','2026-06-10',851,NULL),(41,'Test','2026-06-10',831,NULL),
(121,'Test','2026-06-10',781,NULL),(81,'Test','2026-06-10',780,NULL),
(61,'Test','2026-06-10',775,NULL),(1,'Test','2026-06-10',743,NULL),
(7,'Test','2026-06-10',733,NULL),(123,'Test','2026-06-10',717,NULL);

-- Test bowling, Wed 9 Sep 2026
INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) VALUES
(4,'Test','2026-09-09',NULL,870),(83,'Test','2026-09-09',NULL,861),
(44,'Test','2026-09-09',NULL,826),(63,'Test','2026-09-09',NULL,825),
(43,'Test','2026-09-09',NULL,818),(46,'Test','2026-09-09',NULL,812),
(64,'Test','2026-09-09',NULL,807),(104,'Test','2026-09-09',NULL,800),
(45,'Test','2026-09-09',NULL,795),(32,'Test','2026-09-09',NULL,729),
(47,'Test','2026-09-09',NULL,722),(68,'Test','2026-09-09',NULL,721),
(145,'Test','2026-09-09',NULL,679);

-- Test batting, Wed 16 Sep 2026 (list as reported mid-Sep; date inferred, values differ from 4 Nov)
-- Test bowling, Wed 28 Oct 2026 (second INSERT below)
INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) VALUES
(22,'Test','2026-09-16',861,NULL),(41,'Test','2026-09-16',840,NULL),
(21,'Test','2026-09-16',816,NULL),(42,'Test','2026-09-16',811,NULL),
(61,'Test','2026-09-16',775,NULL),(84,'Test','2026-09-16',740,NULL),
(8,'Test','2026-09-16',713,NULL),(82,'Test','2026-09-16',710,NULL),
(1,'Test','2026-09-16',709,NULL),(121,'Test','2026-09-16',706,NULL),
(7,'Test','2026-09-16',697,NULL),(123,'Test','2026-09-16',689,NULL),
(101,'Test','2026-09-16',684,NULL),(62,'Test','2026-09-16',681,NULL),
(85,'Test','2026-09-16',681,NULL),(103,'Test','2026-09-16',674,NULL),
(181,'Test','2026-09-16',672,NULL),(49,'Test','2026-09-16',670,NULL),
(192,'Test','2026-09-16',662,NULL),(31,'Test','2026-09-16',659,NULL),
(182,'Test','2026-09-16',654,NULL),(48,'Test','2026-09-16',652,NULL),
(69,'Test','2026-09-16',647,NULL),(30,'Test','2026-09-16',630,NULL),
(127,'Test','2026-09-16',627,NULL),(166,'Test','2026-09-16',626,NULL),
(122,'Test','2026-09-16',624,NULL);
INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) VALUES
(63,'Test','2026-10-28',NULL,876),(44,'Test','2026-10-28',NULL,861),
(83,'Test','2026-10-28',NULL,861),(29,'Test','2026-10-28',NULL,856),
(4,'Test','2026-10-28',NULL,853),(46,'Test','2026-10-28',NULL,829),
(43,'Test','2026-10-28',NULL,817),(64,'Test','2026-10-28',NULL,808),
(45,'Test','2026-10-28',NULL,805),(104,'Test','2026-10-28',NULL,777);

-- ICC top-5 tables, Wed 4 Nov 2026 (men) -- as published on icc-cricket.com/rankings
INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) VALUES
-- Test batting
(22,'Test','2026-11-04',861,NULL),(21,'Test','2026-11-04',816,NULL),(42,'Test','2026-11-04',799,NULL),
(61,'Test','2026-11-04',793,NULL),(41,'Test','2026-11-04',790,NULL),
-- Test bowling & Test all-rounders (Marco Jansen, Ravindra Jadeja, Pat Cummins have both batting & bowling)
(44,'Test','2026-11-04',NULL,881),(63,'Test','2026-11-04',510,875),(83,'Test','2026-11-04',NULL,861),
(29,'Test','2026-11-04',NULL,856),(4,'Test','2026-11-04',NULL,853),(6,'Test','2026-11-04',585,830),
(43,'Test','2026-11-04',420,817),
-- ODI batting
(1,'ODI','2026-11-04',841,NULL),(82,'ODI','2026-11-04',794,NULL),(2,'ODI','2026-11-04',781,NULL),
(3,'ODI','2026-11-04',770,NULL),(162,'ODI','2026-11-04',752,NULL),
-- ODI bowling
(161,'ODI','2026-11-04',NULL,760),(65,'ODI','2026-11-04',NULL,660),(88,'ODI','2026-11-04',NULL,644),
(107,'ODI','2026-11-04',NULL,642),(102,'ODI','2026-11-04',NULL,621),
-- T20I batting
(15,'T20I','2026-11-04',889,NULL),(108,'T20I','2026-11-04',883,NULL),(13,'T20I','2026-11-04',862,NULL),
(22,'T20I','2026-11-04',793,NULL),(24,'T20I','2026-11-04',789,NULL),
-- T20I bowling & T20I all-rounders (Hardik Pandya, Glenn Maxwell)
(161,'T20I','2026-11-04',NULL,731),(51,'T20I','2026-11-04',NULL,700),(26,'T20I','2026-11-04',NULL,695),
(107,'T20I','2026-11-04',NULL,695),(88,'T20I','2026-11-04',NULL,676),(11,'T20I','2026-11-04',660,580),
(50,'T20I','2026-11-04',680,490);

-- ICC top-5 tables, Tue 3 Nov 2026 (women)
INSERT INTO PlayerRating (PlayerID, Format, SnapshotDate, BattingPoints, BowlingPoints) VALUES
-- ODI batting & all-rounders (Hayley Matthews, Annabel Sutherland)
(311,'ODI','2026-11-03',782,NULL),(302,'ODI','2026-11-03',762,NULL),(351,'ODI','2026-11-03',731,680),
(324,'ODI','2026-11-03',723,NULL),(325,'ODI','2026-11-03',720,NULL),
-- ODI bowling
(327,'ODI','2026-11-03',NULL,743),(332,'ODI','2026-11-03',NULL,696),(323,'ODI','2026-11-03',NULL,692),
(328,'ODI','2026-11-03',NULL,673),(329,'ODI','2026-11-03',720,667),
-- T20I batting & all-rounders (Deepti Sharma)
(324,'T20I','2026-11-03',787,NULL),(311,'T20I','2026-11-03',766,NULL),(303,'T20I','2026-11-03',759,NULL),
(302,'T20I','2026-11-03',753,723),(326,'T20I','2026-11-03',746,NULL),
-- T20I bowling
(305,'T20I','2026-11-03',NULL,803),(304,'T20I','2026-11-03',NULL,748),(332,'T20I','2026-11-03',NULL,723),
(333,'T20I','2026-11-03',NULL,722),(334,'T20I','2026-11-03',NULL,712);

-- Not stored: the published all-rounder lists (the index is derived = batting x bowling / 1000,
-- and the page gives only the index) and the 4 Nov ODI team ratings (no Matches/Points given).

SET @bulk_load = 0;

-- ---------------------------------------------------------------------
-- Sanity checks (run manually):
--   SELECT COUNT(*) FROM Contests GROUP BY MatchID HAVING COUNT(*) <> 2;   -- expect no rows
--   SELECT m.MatchID FROM CricketMatch m WHERE m.MarginValue IS NOT NULL
--     AND NOT EXISTS (SELECT 1 FROM Contests c WHERE c.MatchID = m.MatchID AND c.Outcome='Win');  -- expect no rows
--   SELECT * FROM v_latest_team_rating WHERE Format='Test' AND Gender='Men';
-- ---------------------------------------------------------------------