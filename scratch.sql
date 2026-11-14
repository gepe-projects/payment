\set VERBOSITY terse

INSERT INTO accounts (name, currency, normal_balance)
VALUES ('bank', 'USD', 'debit') RETURNING id AS bank \gset
INSERT INTO accounts (name, currency, normal_balance)
VALUES ('alice', 'USD', 'credit') RETURNING id AS alice \gset
INSERT INTO accounts (name, currency, normal_balance) RETURNING id as bob \gset


