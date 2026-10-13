"""
account-signals API: the clerk between the warehouse and Slack.

dbt (the brain) decides WHICH signals exist.
This service decides WHO gets each one, writes the message, and makes sure
each signal is sent once, by keeping a logbook in SQLite.

    POST /signals/sync       copy this week's signals into the logbook, once each
    GET  /signals/pending    alerts ready for Slack, message already written
    POST /signals/delivered  n8n calls this after Slack accepted a message
    GET  /signals/log        the whole logbook, for audit
"""
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

import duckdb
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

WAREHOUSE = "warehouse.duckdb"   # built by dbt; we only ever read it
LOGBOOK = "signals_log.db"       # ours; remembers what was sent

app = FastAPI(title="account-signals")


# ---------- the two stores ----------

@contextmanager
def warehouse():
    """Opens the warehouse read-only, and closes it right after.
    Holding it open would block `dbt build`: DuckDB allows one writer at a time."""
    try:
        con = duckdb.connect(WAREHOUSE, read_only=True)
    except duckdb.Error as e:
        raise HTTPException(503, f"Can't open the warehouse (is dbt running?): {e}")
    try:
        yield con
    finally:
        con.close()


def rows(con, sql):
    cur = con.execute(sql)
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


@contextmanager
def logbook():
    con = sqlite3.connect(LOGBOOK)
    con.row_factory = sqlite3.Row
    con.execute("""
        CREATE TABLE IF NOT EXISTS alert_log (
            signal_key        TEXT PRIMARY KEY,  -- account|signal|week: the send-once key
            account_id        TEXT NOT NULL,
            signal_type       TEXT NOT NULL,
            status            TEXT NOT NULL,     -- pending | delivered | suppressed
            suppressed_reason TEXT,
            route_to_role     TEXT NOT NULL,     -- the role the rule asked for
            owner_name        TEXT NOT NULL,     -- the person who actually gets it
            owner_role        TEXT NOT NULL,
            slack_handle      TEXT,
            routed_via        TEXT NOT NULL,     -- owner | revops_fallback
            slack_text        TEXT NOT NULL,
            rule_version      INTEGER,
            detected_at       TEXT NOT NULL,
            delivered_at      TEXT
        )
    """)
    try:
        yield con
        con.commit()
    finally:
        con.close()


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ---------- routing and the message ----------

def pick_owner(signal, owners):
    """The account's CSM (for drops) or AE (for expansion).
    If that seat is empty, RevOps catches it, so no alert falls on the floor."""
    owner_id = signal["csm_owner_id"] if signal["route_to_role"] == "CSM" else signal["ae_owner_id"]
    if owner_id and owner_id in owners:
        return owners[owner_id], "owner"
    revops = [o for o in owners.values() if o["owner_role"] == "RevOps"]
    if not revops:
        raise HTTPException(500, f"{signal['account_id']} has no {signal['route_to_role']} and there is no RevOps fallback")
    return revops[0], "revops_fallback"


def write_message(s, ws, owner, routed_via):
    name = f"{s['account_name']} ({s['account_id']})"
    if s["signal_type"] == "usage_drop":
        lines = [
            f":small_red_triangle_down: *Usage drop* | {name}",
            f"Active users {s['last_week_users']} → {s['this_week_users']} "
            f"({s['utilization_change_pct']:+.1f}%) on {s['seats']} seats",
            f"ARR ${s['arr_usd']:,.0f} · renews {s['renewal_date']}",
        ]
    else:
        lines = [
            f":chart_with_upwards_trend: *Expansion chance* | {name}",
            f"Utilization {s['this_week_utilization']:.2f} "
            f"({s['this_week_users']} active users on {s['seats']} seats)",
            f"Not owned yet: {ws['products']} "
            f"(up to ${ws['potential_arr']:,.0f} ARR at list price)",
        ]
    who = f"{owner['owner_name']} ({owner['owner_role']})"
    if owner["slack_handle"]:
        who += f" {owner['slack_handle']}"
    if routed_via == "revops_fallback":
        who += f", because no {s['route_to_role']} is assigned"
    lines.append(f"Owner: {who}")
    return "\n".join(lines)


# ---------- endpoints ----------

@app.get("/health")
def health():
    return {"ok": True}


@app.post("/signals/sync")
def sync_signals():
    """Reads signal_changes and logs each signal ONCE.
    Run it ten times: the first run logs 7, the other nine log 0."""
    with warehouse() as wh:
        signals = rows(wh, """
            select s.*, a.ae_owner_id, a.csm_owner_id, a.arr_usd, a.renewal_date
            from signal_changes as s
            join stg_accounts as a on a.account_id = s.account_id
            order by s.signal_key
        """)
        owners = {o["owner_id"]: o for o in rows(wh, "select * from stg_owners")}
        whitespace = {w["account_id"]: w for w in rows(wh, """
            select account_id,
                   string_agg(product_name, ', ' order by product_id) as products,
                   sum(potential_arr_usd)                             as potential_arr
            from int_account_whitespace
            group by account_id
        """)}

    detected_at = now()
    new = 0
    with logbook() as log:
        for s in signals:
            owner, routed_via = pick_owner(s, owners)
            status = "suppressed" if s["status"] == "suppressed" else "pending"
            cur = log.execute(
                """INSERT OR IGNORE INTO alert_log
                   (signal_key, account_id, signal_type, status, suppressed_reason,
                    route_to_role, owner_name, owner_role, slack_handle, routed_via,
                    slack_text, rule_version, detected_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (s["signal_key"], s["account_id"], s["signal_type"], status, s["suppressed_reason"],
                 s["route_to_role"], owner["owner_name"], owner["owner_role"], owner["slack_handle"],
                 routed_via, write_message(s, whitespace.get(s["account_id"]), owner, routed_via),
                 s["rule_version"], detected_at),
            )
            new += cur.rowcount   # 1 if inserted, 0 if this key was already in the logbook
    return {"signals_in_warehouse": len(signals), "new": new, "already_logged": len(signals) - new}


@app.get("/signals/pending")
def pending_alerts():
    """What n8n should send now: logged, not suppressed, not yet delivered."""
    with logbook() as log:
        found = log.execute("""
            SELECT signal_key, account_id, signal_type, owner_name, owner_role,
                   slack_handle, routed_via, slack_text
            FROM alert_log
            WHERE status = 'pending'
            ORDER BY signal_key
        """).fetchall()
    return [dict(r) for r in found]


class Delivered(BaseModel):
    signal_key: str


@app.post("/signals/delivered")
def mark_delivered(body: Delivered):
    """n8n confirms Slack took the message. Safe to call twice."""
    with logbook() as log:
        row = log.execute("SELECT status FROM alert_log WHERE signal_key = ?", (body.signal_key,)).fetchone()
        if row is None:
            raise HTTPException(404, f"Unknown signal_key: {body.signal_key}")
        if row["status"] == "suppressed":
            raise HTTPException(409, f"{body.signal_key} is suppressed and must not be sent")
        if row["status"] == "delivered":
            return {"signal_key": body.signal_key, "status": "delivered", "changed": False}
        at = now()
        log.execute("UPDATE alert_log SET status = 'delivered', delivered_at = ? WHERE signal_key = ?",
                    (at, body.signal_key))
    return {"signal_key": body.signal_key, "status": "delivered", "changed": True, "delivered_at": at}


@app.get("/signals/log")
def full_log():
    """Everything ever logged, including suppressed signals, for audit."""
    with logbook() as log:
        return [dict(r) for r in log.execute("SELECT * FROM alert_log ORDER BY signal_key").fetchall()]
