"""
generate_data.py

Gera um banco SQLite com dados SINTÉTICOS (fictícios) de contas, transações
e alertas de fraude, no estilo de um ambiente de meios de pagamento (Pix,
P2P, Boleto, IPVA). Nenhum dado real ou confidencial é usado aqui , tudo é
gerado aleatoriamente para fins de portfólio.

Uso:
    python3 generate_data.py

Gera o arquivo fraud_analytics.db na mesma pasta.
"""

import sqlite3
import random
from datetime import date, datetime, timedelta

random.seed(42)

DB_PATH = "fraud_analytics.db"

STATES_CITIES = [
    ("ES", "Vitória"), ("ES", "Vila Velha"), ("ES", "Serra"),
    ("SP", "São Paulo"), ("SP", "Campinas"),
    ("RJ", "Rio de Janeiro"), ("RJ", "Niterói"),
    ("MG", "Belo Horizonte"), ("BA", "Salvador"), ("PR", "Curitiba"),
]

PRODUCTS = ["Pix", "P2P", "Boleto", "IPVA"]
STATUSES = ["approved", "blocked", "refused", "on_hold"]
ALERT_TYPES = [
    "central_falsa", "cnpj_recente", "autofraude",
    "rede_conexao", "valor_atipico", "fraude_amigavel",
]
RESOLUTIONS = ["fraud_confirmed", "false_positive", "pending"]

SIM_START = date(2026, 1, 1)
SIM_END = date(2026, 6, 30)


def random_date(start, end):
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))


def build_accounts(n=300):
    accounts = []
    for account_id in range(1, n + 1):
        state, city = random.choice(STATES_CITIES)
        account_type = random.choices(["PF", "PJ"], weights=[0.8, 0.2])[0]
        created_at = random_date(date(2023, 1, 1), SIM_END)
        # PJ accounts get a "cnpj age" in days as of SIM_END, useful for
        # detecting payments to recently-opened CNPJs
        cnpj_age_days = (SIM_END - created_at).days if account_type == "PJ" else None
        accounts.append((account_id, created_at.isoformat(), city, state, account_type, cnpj_age_days))
    return accounts


def build_transactions(accounts, n=5000):
    transactions = []
    account_ids = [a[0] for a in accounts]
    for transaction_id in range(1, n + 1):
        account_id = random.choice(account_ids)
        counterparty_id = random.choice(account_ids)
        while counterparty_id == account_id:
            counterparty_id = random.choice(account_ids)
        product = random.choices(PRODUCTS, weights=[0.5, 0.25, 0.15, 0.10])[0]
        # amounts: mostly small/medium, a long tail of high values (mimics real skew)
        base = random.lognormvariate(4.2, 1.0)
        amount = round(min(base, 15000), 2)
        created_at = random_date(SIM_START, SIM_END)
        created_dt = datetime.combine(created_at, datetime.min.time()) + timedelta(
            hours=random.randint(0, 23), minutes=random.randint(0, 59)
        )
        status = random.choices(STATUSES, weights=[0.82, 0.06, 0.05, 0.07])[0]
        transactions.append((
            transaction_id, account_id, counterparty_id, product,
            amount, created_dt.isoformat(sep=" "), status,
        ))
    return transactions


def build_alerts(transactions, rate=0.10):
    alerts = []
    alert_id = 1
    sample = random.sample(transactions, int(len(transactions) * rate))
    for t in sample:
        transaction_id = t[0]
        alert_type = random.choice(ALERT_TYPES)
        risk_score = round(random.uniform(0.3, 0.99), 2)
        created_dt = datetime.fromisoformat(t[5]) + timedelta(minutes=random.randint(1, 120))
        resolution = random.choices(RESOLUTIONS, weights=[0.35, 0.45, 0.20])[0]
        alerts.append((alert_id, transaction_id, alert_type, risk_score, created_dt.isoformat(sep=" "), resolution))
        alert_id += 1
    return alerts


def main():
    accounts = build_accounts()
    transactions = build_transactions(accounts)
    alerts = build_alerts(transactions)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.executescript("""
    DROP TABLE IF EXISTS alerts;
    DROP TABLE IF EXISTS transactions;
    DROP TABLE IF EXISTS accounts;

    CREATE TABLE accounts (
        account_id      INTEGER PRIMARY KEY,
        created_at      TEXT NOT NULL,
        city            TEXT NOT NULL,
        state           TEXT NOT NULL,
        account_type    TEXT NOT NULL CHECK (account_type IN ('PF', 'PJ')),
        cnpj_age_days   INTEGER
    );

    CREATE TABLE transactions (
        transaction_id      INTEGER PRIMARY KEY,
        account_id          INTEGER NOT NULL REFERENCES accounts(account_id),
        counterparty_id     INTEGER NOT NULL REFERENCES accounts(account_id),
        product             TEXT NOT NULL,
        amount              REAL NOT NULL,
        created_at          TEXT NOT NULL,
        status              TEXT NOT NULL
    );

    CREATE TABLE alerts (
        alert_id        INTEGER PRIMARY KEY,
        transaction_id  INTEGER NOT NULL REFERENCES transactions(transaction_id),
        alert_type      TEXT NOT NULL,
        risk_score      REAL NOT NULL,
        created_at      TEXT NOT NULL,
        resolution      TEXT NOT NULL
    );

    CREATE INDEX idx_transactions_account ON transactions(account_id);
    CREATE INDEX idx_transactions_created ON transactions(created_at);
    CREATE INDEX idx_alerts_transaction ON alerts(transaction_id);
    """)

    cur.executemany("INSERT INTO accounts VALUES (?,?,?,?,?,?)", accounts)
    cur.executemany("INSERT INTO transactions VALUES (?,?,?,?,?,?,?)", transactions)
    cur.executemany("INSERT INTO alerts VALUES (?,?,?,?,?,?)", alerts)

    conn.commit()
    conn.close()

    print(f"OK: {len(accounts)} contas, {len(transactions)} transações, {len(alerts)} alertas -> {DB_PATH}")


if __name__ == "__main__":
    main()
