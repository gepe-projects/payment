package wallet

import (
	"context"
	"errors"
	"fmt"
	"github.com/gepe-projects/payment/internal/wallet/walletdb"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"math"
	"uuid"
)

// The generated models double as our domain types for now. The aliases mean
// callers only ever import package wallet, never walletdb.

type (
	Account        = walletdb.Account
	AccountBalance = walletdb.AccountBalance
	Entry          = walletdb.Entry
	NewAccount     = walletdb.CreateAccountParams
	Direction      = walletdb.EntryDirection
)

const (
	Debit  = walletdb.EntryDirectionDebit
	Credit = walletdb.EntryDirectionCredit
)

// ErrAccountNotFound is returned when an account does not exist.
var ErrAccountNotFound = errors.New("wallet: account not found")

type Store struct {
	pool *pgxpool.Pool
	q    *walletdb.Queries
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{
		pool: pool,
		q:    walletdb.New(pool),
	}
}

// CreateAccount opens a new account. OwnerID is nil for system accounts.
func (s *Store) CreateAccount(ctx context.Context, account NewAccount) (Account, error) {
	acc, err := s.q.CreateAccount(ctx, account)
	if err != nil {
		return Account{}, fmt.Errorf("create account: %w", err)
	}

	return acc, nil
}

// Account returns the account with the given id.
func (s *Store) Account(ctx context.Context, id uuid.UUID) (Account, error) {
	acc, err := s.q.GetAccount(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Account{}, ErrAccountNotFound
		}
		return Account{}, fmt.Errorf("get account: %w", err)
	}
	return acc, nil
}

// Balance returns an account's balance, derived from its entries by the
// account_balances view. Amounts are minor units of the account's currency.
func (s *Store) Balance(ctx context.Context, id uuid.UUID) (AccountBalance, error) {
	b, err := s.q.GetAccountBalance(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return AccountBalance{}, ErrAccountNotFound
		}
		return AccountBalance{}, fmt.Errorf("get balance %s: %w", id, err)
	}

	return b, nil
}

// Entries returns a page of an account's entries, newest first. Pass 0 as
// before for the first page, then the id of the last entry you received.
func (s *Store) Entries(ctx context.Context, id uuid.UUID, before int64, limit int32) ([]Entry, error) {
	if before <= 0 {
		before = math.MaxInt64
	}

	entries, err := s.q.ListEntriesByAccount(ctx, walletdb.ListEntriesByAccountParams{
		AccountID: id,
		BeforeID:  before,
		PageSize:  limit,
	})
	if err != nil {
		return []Entry{}, fmt.Errorf("list entries: %w", err)
	}
	if len(entries) == 0 {
		return []Entry{}, nil
	}
	return entries, nil
}
