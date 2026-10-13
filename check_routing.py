"""
Checks the logbook's routing against answer_key/expected_accounts.csv.
Every detected signal, suppressed ones included, must be assigned to the
person the answer key names. Run it after POST /signals/sync.
"""
import csv
import sqlite3

expected = {}
with open("answer_key/expected_accounts.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        # routed_to looks like "usage_drop: Jules Renwicke; expansion: Tessa Marlowen"
        for part in filter(None, (p.strip() for p in row["routed_to"].split(";"))):
            signal, person = (x.strip() for x in part.split(":", 1))
            expected[(row["account_id"], signal)] = person

con = sqlite3.connect("signals_log.db")
actual = {
    (account, signal): (owner, status)
    for account, signal, owner, status in con.execute(
        "SELECT account_id, signal_type, owner_name, status FROM alert_log")
}
con.close()

problems = 0
for key in sorted(set(expected) | set(actual)):
    want = expected.get(key)
    got, status = actual.get(key, (None, None))
    ok = want == got
    problems += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {key[0]}  {key[1]:<11} expected {want!s:<16} got {got!s:<16} [{status}]")

print(f"\n{len(expected)} expected, {len(actual)} logged, {problems} problems")
