"""test_operations.py - Unit tests for business rules and operations integrity checks."""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Ensure src/ is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from database import OperationError
import operations as ops


class TestOperationsValidation(unittest.TestCase):
    def test_add_match_identical_teams_rejected(self):
        # C6: A match must have two different teams
        with self.assertRaises(OperationError) as ctx:
            ops.add_match(1, 1, "2026-08-01", "2026-08-05", "IND", "IND", scheduled_days=5)
        self.assertIn("C6", str(ctx.exception))

    def test_add_match_missing_teams_rejected(self):
        with self.assertRaises(OperationError):
            ops.add_match(1, 1, "2026-08-01", "2026-08-05", "", "AUS")

    def test_register_player_empty_name_rejected(self):
        with self.assertRaises(OperationError) as ctx:
            ops.register_player("", "Sharma", "1987-04-30", "Men", "IND")
        self.assertIn("Both a first name and a last name are required", str(ctx.exception))

    def test_register_player_invalid_gender_rejected(self):
        with self.assertRaises(OperationError) as ctx:
            ops.register_player("Virat", "Kohli", "1988-11-05", "Other", "IND")
        self.assertIn("Gender must be Men or Women", str(ctx.exception))

    def test_set_eligible_formats_empty_rejected(self):
        with self.assertRaises(OperationError) as ctx:
            ops.set_eligible_formats("IND", [])
        self.assertIn("Choose between one and three formats", str(ctx.exception))

    def test_set_eligible_formats_invalid_format_rejected(self):
        with self.assertRaises(OperationError):
            ops.set_eligible_formats("IND", ["Test", "InvalidFormat"])

    def test_move_appearances_same_player_rejected(self):
        with self.assertRaises(OperationError) as ctx:
            ops.move_appearances(10, 10)
        self.assertIn("Choose two different players", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
