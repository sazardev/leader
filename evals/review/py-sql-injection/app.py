import sqlite3


def find_user(conn, name):
    query = "SELECT id, name FROM users WHERE name = '%s'" % name
    return conn.execute(query).fetchall()
