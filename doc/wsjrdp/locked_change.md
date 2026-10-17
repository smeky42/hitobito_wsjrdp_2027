# Locked changes

`Wsjrdp::LockedChange` runs a block in a transaction of its own, under locks
that are all taken before the block runs. It keeps two requests that change
the same thing at the same moment apart -- two uploads into one slot, or two
uploads of one person whose status depends on both -- without deadlocks.
`Wsjrdp2027::DocumentWrite` is built on it (`doc/wsjrdp/documents.md`,
"Writing documents").

```ruby
Wsjrdp::LockedChange.run(rows: [person], keys: [key], timeout: 8.seconds) do |change|
  # fast database work only
  change.after_commit { ... }  # mails, jobs, answers
  change.on_rollback { ... }   # undo what lies outside the database
end
```

## The locks

- **rows**: records, locked with `SELECT ... FOR NO KEY UPDATE` and reloaded.
  Other updates and row locks of them wait until the change commits; plain
  reads do not wait, nor do inserts into tables that refer to them (their
  foreign-key check takes `FOR KEY SHARE`, which `FOR NO KEY UPDATE` lets
  through). A row must have no unsaved changes.
- **keys**: strings, each an advisory lock of the transaction:
  `pg_advisory_xact_lock(hashtextextended(key, 0))`. It needs no row and ends
  with the transaction, also when the process dies. Two keys with the same
  hash share one lock: they wait for each other without need, but nothing
  goes wrong. A key names what it locks completely, e.g.
  `DocumentWrite.lock_key`:
  `["wsjrdp_documents","Person",123,"contract",0,"",0]`.

## No deadlocks

A deadlock needs a circle: one change holds A and waits for B, another holds
B and waits for A. A locked change takes all its locks at the start, in one
order -- the rows ordered by table and id, then the keys ordered by their
hash, duplicates left out -- and takes none later. So two locked changes
never wait for each other in a circle.

Against other code, which takes no advisory locks: while a change waits for
its first row it holds nothing; once it has its rows it waits only for keys,
which only locked changes take, and for rows that only locked changes write.
The rule that keeps it so: whatever changes the slots of `wsjrdp_documents`
does so through a locked change, or locks its rows in the same order first --
the soft delete of a destroyed person locks the person's row before it marks
the person's documents deleted. A statement that stamps many rows at once
(`WsjrdpDocument.stamp_checked`, `file_checked_at`) takes them with `SKIP
LOCKED`: it never waits, so it cannot close a circle, and a writer waits for
it no longer than the statement takes. Should a deadlock happen anyway,
PostgreSQL ends one of the transactions after `deadlock_timeout`; the change
rolls back and runs `on_rollback`.

## Waiting

The change sets `SET LOCAL lock_timeout` (default 8 seconds). A lock that is
not free by then raises `Wsjrdp::LockedChange::Busy` (an
`ActiveRecord::LockWaitTimeout`); the change has rolled back, and the user can
try again.

## The block

- Only fast database work: reads, updates of the locked rows, inserts. A
  further row to change belongs into `rows:`.
- No mails, no calls to other services: `change.after_commit` runs after the
  commit.
- `change.on_rollback` runs when the block raises (also `ActiveRecord::Rollback`)
  or the commit fails, e.g. to remove files that were written.

## Transactions

`run` refuses an open transaction (`NestedTransaction`): the change's commit
would not be a commit, and its `on_rollback` would not run when the enclosing
transaction rolls back. Inside a transaction that is not joinable -- the one
around a spec -- it runs in a savepoint and the end of the block counts as
the commit; it restores the lock timeout of the enclosing transaction.

Specs of two changes at once need two connections and transactions that
really commit: `spec/domain/wsjrdp_2027/document_write_concurrency_spec.rb`
runs without the transaction around each example and undoes its writes
itself.
