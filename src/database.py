"""database.py - the only place that knows how to reach MySQL.

Every read and write in the project goes through the helpers here and uses
raw, parameterised SQL (%s placeholders). No ORM, no query builder.
"""
import os
from contextlib import contextmanager

try:
    import pymysql
    import pymysql.cursors
    MySQLError = pymysql.MySQLError
except ImportError:
    pymysql = None
    class MySQLError(Exception):
        pass


class OperationError(Exception):
    """A user-facing error (constraint violation, bad input, missing record)."""


def get_db_config():
    """Database settings in one place (environment variables or defaults)."""
    cfg = {
        "host": os.environ.get("DB_HOST", "localhost"),
        "port": int(os.environ.get("DB_PORT", "3306")),
        "user": os.environ.get("DB_USER", "root"),
        "password": os.environ.get("DB_PASS", ""),
        "database": os.environ.get("DB_NAME", "icc_rankings_db"),
        "charset": "utf8mb4",
    }
    if os.environ.get("DB_SOCKET"):
        cfg["unix_socket"] = os.environ["DB_SOCKET"]
    return cfg


def get_connection():
    if pymysql is None:
        raise OperationError("PyMySQL is not installed. Please install dependencies: pip install -r requirements.txt")
    return pymysql.connect(
        **get_db_config(),
        cursorclass=pymysql.cursors.DictCursor,  # rows as dictionaries
        autocommit=False,                         # writes are committed manually
    )


def friendly_error(e):
    """Turn a MySQL error into a short message that can be shown to the user."""
    code = e.args[0] if e.args else 0
    msg = e.args[1] if len(e.args) > 1 else str(e)
    if code == 1644:      # SIGNAL from our triggers: message is already readable
        return msg
    if code == 3819:      # CHECK constraint
        return "A value breaks a data rule: " + msg
    if code == 1062:
        return "That record already exists (duplicate key)."
    if code == 1451:
        return ("Cannot delete or change this record because other records still "
                "depend on it (for example a player with appearances, or a team, "
                "series or venue that is still referenced).")
    if code == 1452:
        return "A referenced record does not exist (check the team, series, venue or player chosen)."
    if code in (1048, 1364):
        return "A required value is missing."
    if code in (1265, 1292, 1366, 1411):
        return "A value or date has the wrong format."
    return "Database error (%s): %s" % (code, msg)


# ---------------------------- reads ----------------------------------
def query_all(sql, params=()):
    """Run a SELECT and return every row as a dict."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()
    except MySQLError as e:
        raise OperationError(friendly_error(e)) from e
    finally:
        conn.close()


def query_one(sql, params=()):
    rows = query_all(sql, params)
    return rows[0] if rows else None


# ---------------------------- writes ---------------------------------
@contextmanager
def transaction():
    """Yield a cursor; commit on success, roll back and raise OperationError on failure."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            yield cur
        conn.commit()
    except MySQLError as e:
        conn.rollback()
        raise OperationError(friendly_error(e)) from e
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()