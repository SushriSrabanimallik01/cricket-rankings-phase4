"""test_database.py - Unit tests for database connection and error formatting."""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Ensure src/ is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from database import OperationError, friendly_error, get_db_config


class TestDatabaseConfig(unittest.TestCase):
    def test_default_config(self):
        cfg = get_db_config()
        self.assertIn("host", cfg)
        self.assertIn("port", cfg)
        self.assertIn("user", cfg)
        self.assertIn("database", cfg)
        self.assertEqual(cfg["database"], os.environ.get("DB_NAME", "icc_rankings_db"))

    def test_environment_overrides(self):
        with patch.dict(os.environ, {"DB_HOST": "db.example.com", "DB_PORT": "3307", "DB_NAME": "test_cricket"}):
            cfg = get_db_config()
            self.assertEqual(cfg["host"], "db.example.com")
            self.assertEqual(cfg["port"], 3307)
            self.assertEqual(cfg["database"], "test_cricket")


class TestFriendlyErrors(unittest.TestCase):
    def test_trigger_signal_1644(self):
        err = MagicMock()
        err.args = (1644, "C6: a match has exactly two teams")
        msg = friendly_error(err)
        self.assertEqual(msg, "C6: a match has exactly two teams")

    def test_check_constraint_3819(self):
        err = MagicMock()
        err.args = (3819, "Check constraint 'ck_player_first' is violated.")
        msg = friendly_error(err)
        self.assertTrue(msg.startswith("A value breaks a data rule:"))

    def test_duplicate_key_1062(self):
        err = MagicMock()
        err.args = (1062, "Duplicate entry 'IND' for key 'PRIMARY'")
        msg = friendly_error(err)
        self.assertIn("already exists", msg)

    def test_foreign_key_restrict_1451(self):
        err = MagicMock()
        err.args = (1451, "Cannot delete or update a parent row")
        msg = friendly_error(err)
        self.assertIn("depend on it", msg)

    def test_foreign_key_missing_1452(self):
        err = MagicMock()
        err.args = (1452, "Cannot add or update a child row")
        msg = friendly_error(err)
        self.assertIn("does not exist", msg)

    def test_required_missing_1048(self):
        err = MagicMock()
        err.args = (1048, "Column 'FirstName' cannot be null")
        msg = friendly_error(err)
        self.assertEqual(msg, "A required value is missing.")


if __name__ == "__main__":
    unittest.main()
