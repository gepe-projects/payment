BEGIN;

-- debit or credit: two side of every entry
CREATE TYPE entry_direction AS ENUM ('debit', 'credit');

-- akun itu semua yang pegang duit: user wallet, bank account yang deposit semua saldo user,
-- atau system account dll deh
CREATE TABLE accounts
(
    id             uuid PRIMARY KEY         DEFAULT gen_random_uuid(),
    -- user dari auth service, null jika itu system
    owner_id       uuid,
    name           text            NOT NULL CHECK ( name <> '' ),
    currency       text            NOT NULL check ( currency ~ '^[A-Z]{3}$' ),
    normal_balance entry_direction NOT NULL,
    created_at     timestamptz     NOT NULL DEFAULT now(),

    UNIQUE (id, currency)
);

CREATE INDEX accounts_owner_id_idx ON accounts (owner_id) WHERE owner_id IS NOT NULL;

-- journal: satu baris per uang yang pindah
CREATE TABLE transactions
(
    id          uuid PRIMARY KEY     DEFAULT gen_random_uuid(),
    description text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- one line of  transaction: an account debited or creadited to an account
CREATE TABLE entries
(
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id uuid            NOT NULL references transactions (id),
    account_id     uuid            NOT NULL,
    direction      entry_direction not null,
    amount         bigint          NOT NULL CHECK ( amount > 0 ),
    currency       text            NOT NULL,
    created_at     timestamptz     NOT NULL DEFAULT now(),

    -- an entry currency mustmatch its account currency
    FOREIGN KEY (account_id, currency) REFERENCES accounts (id, currency)
);

-- poatgres ga ngindex foreign key otomatis
CREATE INDEX entries_transaction_id_idx ON entries (transaction_id);
CREATE INDEX entries_account_id_idx ON entries (account_id);


-- setiap transaksi harus punya entries, dan debit harus seimbang dengan kredit
-- in every currency. checked at COMMIT, once all the entries exist
CREATE FUNCTION check_transaction_balanced() RETURNS trigger
    LANGUAGE plpgsql AS
$$
DECLARE
    tx_id uuid;
BEGIN
    IF tg_table_name = 'transactions' THEN
        tx_id := NEW.id;
    ELSE
        tx_id = NEW.transaction_id;
    END IF;

    IF NOT EXISTS(SELECT 1 FROM entries WHERE transaction_id = tx_id) THEN
        RAISE EXCEPTION 'transaction % has no entries', tx_id
            USING ERRCODE = 'check_violation';
    end if;

    IF EXISTS(SELECT 1
              FROM entries
              WHERE transaction_id = tx_id
              GROUP BY currency
              -- ini bukan berarti debit plus dan credit minus. ini cuma buat mastiin sum nya harus 0 atau seimbang
              HAVING sum(CASE direction WHEN 'debit' THEN amount ELSE -amount END) <> 0) THEN
        RAISE EXCEPTION 'transaction % is not balanced', tx_id
            USING ERRCODE = 'check_violation';
    end if;

    RETURN NULL;
end;
$$;



CREATE CONSTRAINT TRIGGER transactions_balanced
    AFTER INSERT
    on transactions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION check_transaction_balanced();

CREATE CONSTRAINT TRIGGER entries_balanced
    AFTER INSERT
    ON entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE FUNCTION check_transaction_balanced();


-- ledger itu append-only: kesalahan harus di perbaiki dengan pembalikan transaction atau reversing transaction
CREATE FUNCTION forbid_ledger_changes() RETURNS TRIGGER
    LANGUAGE plpgsql AS
$$
BEGIN
    RAISE EXCEPTION '% is append_only, post a reversing transaction instead', tg_table_name
        USING ERRCODE = 'restrict_violation';
end;
$$;


CREATE TRIGGER transactions_append_only
    BEFORE UPDATE OR DELETE
    ON transactions
    FOR EACH ROW
EXECUTE FUNCTION forbid_ledger_changes();

CREATE TRIGGER entries_appen_only
    BEFORE UPDATE OR DELETE
    ON entries
    FOR EACH ROW
EXECUTE FUNCTION forbid_ledger_changes();


-- balances are derived from entries, never stored.
CREATE VIEW account_balances AS
SELECT a.id                   AS account_id,
       a.name,
       a.currency,
       coalesce(sum(
                        CASE WHEN e.direction = a.normal_balance THEN e.amount ELSE -e.amount END
                ), 0)::bigint AS balance
FROM accounts a
         LEFT JOIN entries e on a.id = e.account_id
GROUP BY a.id;



COMMIT;

