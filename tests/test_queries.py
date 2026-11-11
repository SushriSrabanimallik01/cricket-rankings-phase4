"""test_queries.py - Unit tests for query helper functions and SQL security."""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Ensure src/ is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

import queries as qry


class TestQueryHelpers(unittest.TestCase):
    def test_like_pattern_escaping(self):
        # Empty inputs should return None
        self.assertIsNone(qry.like_pattern(""))
        self.assertIsNone(qry.like_pattern("   "))
        self.assertIsNone(qry.like_pattern(None))

        # Standard search text
        self.assertEqual(qry.like_pattern("India"), "%India%")
        self.assertEqual(qry.like_pattern("  SHA  "), "%SHA%")

        # Wildcards escaped to prevent SQL LIKE injection
        self.assertEqual(qry.like_pattern("100%"), "%100\\%%")
        self.assertEqual(qry.like_pattern("under_score"), "%under\\_score%")
        self.assertEqual(qry.like_pattern("back\\slash"), "%back\\\\slash%")

    def test_player_lists_whitelist(self):
        # Ensure only allowed columns are whitelisted
        self.assertIn("batting", qry.PLAYER_LISTS)
        self.assertIn("bowling", qry.PLAYER_LISTS)
        self.assertIn("allrounder", qry.PLAYER_LISTS)
        points_col, rank_col = qry.PLAYER_LISTS["batting"]
        self.assertEqual(points_col, "BattingPoints")
        self.assertEqual(rank_col, "BattingRank")

    @patch("queries.query_all")
    def test_list_teams_parameterized(self, mock_query):
        mock_query.return_value = [{"ICC_Code": "IND", "TeamName": "India"}]
        res = qry.list_teams("Test")
        mock_query.assert_called_once()
        sql, params = mock_query.call_args[0]
        # Query purity verification: SQL must use %s placeholders
        self.assertIn("%s", sql)
        self.assertEqual(params, ("Test", "Test"))
        self.assertEqual(len(res), 1)

    @patch("queries.query_all")
    def test_search_players_query(self, mock_query):
        mock_query.return_value = [{"PlayerID": 1, "FirstName": "Rohit", "LastName": "Sharma"}]
        res = qry.search_players("SHA")
        mock_query.assert_called_once()
        sql, params = mock_query.call_args[0]
        self.assertIn("LOWER(p.FirstName) LIKE LOWER(%s)", sql)
        self.assertEqual(params, ("%SHA%", "%SHA%"))
        self.assertEqual(res[0]["LastName"], "Sharma")


if __name__ == "__main__":
    unittest.main()
