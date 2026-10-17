# Stored documents

`wsjrdp_documents` holds one row per stored file: whose it is (the subject),
what kind of document it is (its keys), which version, who may read, write and
hide it, and where the file lies. The files themselves lie on disk under the
upload root, next to the registration uploads; there is no ActiveStorage.

| Part | Where |
|---|---|
| Model | `WsjrdpDocument` (`app/models/wsjrdp_document.rb`) |
| File names | `Wsjrdp2027::DocumentFilename` |
| Subject kinds | `Wsjrdp2027::DocumentSubjects` |
| Kinds of document | `WsjrdpDocumentKind` (`wsjrdp_document_kinds`) |
| Writing files and rows | `Wsjrdp2027::DocumentStore` |
| Who may what | `Wsjrdp2027::DocumentAccess`, used by `Wsjrdp2027::Ability` |
| Download, upload | `Wsjrdp::DocumentsController`, `wsjrdp/documents/_upload_form` |
| JSON:API (read only) | `DocumentResource`, `JsonApi::DocumentsController` |

## Subject

A document belongs to a subject (`subject_type`, `subject_id`). The register
`Wsjrdp2027::DocumentSubjects` names the kinds of subject and per kind its
folder and the access entries that mean something for it. Only `Person` is a
kind; a document of another subject is refused.

A new kind needs:

- an entry in the register (folder, entries);
- what `Person#soft_delete_wsjrdp_documents` does for a person: hide the
  documents when the subject is destroyed;
- a non-negative integer id, as the file name holds it.

## Keys and slots

`key`, `key_number`, `secondary_key` and `secondary_key_number` say what kind
of document it is and which of several (0 where there is one), e.g.
`deregistration` 2, `signed_form` 0. Together with `derived_from_id` and
`derivation_key` they name a slot, which holds at most one current document
(index `index_wsjrdp_documents_current`).

A key (`key`, `secondary_key`, `derivation_key`):

- consists of `a-z`, `0-9` and `_` and starts with a letter -- `-` separates
  the parts of a file name and is never part of a key;
- is at most 40 characters long;
- contains no `__`;
- does not end in `_`.

The model checks this (`DocumentFilename.key_error`); the file name relies on
it.

## Versions

`status` is `current`, `superseded` or `deleted`.

- Replacing a document stores a new one with `replaces_id`; the old one
  becomes `superseded` with `superseded_at`, in the same transaction. A
  document may be followed by several (`replacements`), e.g. when one scan is
  split up. The replacement takes the keys and lists of the document it
  replaces.
- Hiding sets `deleted` and `deleted_at` (`DocumentStore.hide!`); the file
  stays. Nothing deletes files.
- A derivation (`derived_from_id`, `derivation_key`, e.g. a preview) takes the
  subject and keys of its original and is deleted with it.

## Missing files

`file_status` says whether the file exists: `present` or `missing`, apart
from `status`, which is about versions -- a superseded document may have a
missing file too. `file_checked_at` is when that was last found out. A
document whose file is missing keeps its row and its name, e.g. a
registration upload whose file is gone, so its chain of versions stays whole;
its `byte_size` and `content_sha256` may be unknown. The download answers 404
for a missing file.

Two runs find it out again:

- registering the registration uploads (below) checks the files of their
  chains;
- "Alle Dateien prüfen" on the overview of the Dokumentenverwaltung
  (`DocumentManagementController#check_files`,
  `Wsjrdp2027::CheckDocumentFilesJob`, `Wsjrdp2027::DocumentFileCheck`)
  checks every row, whatever its kind and status, in the background: a row
  whose file is gone becomes `missing`, one whose file is back `present`
  with its size and SHA-256 (and its type, if it had none;
  `Wsjrdp2027::DocumentFileData`). Every row checked gets
  `file_checked_at` -- except a row someone writes at that moment, which the
  writer stamps (`WsjrdpDocument.stamp_checked`, `SKIP LOCKED`: the statement
  never waits). A row with an empty path, or one the store refuses,
  counts as missing. Each folder is listed once.

## Who may what

Three lists name entries; one entry the viewer meets suffices:

| List | Gives | Default |
|---|---|---|
| `readable_by` | download, the JSON:API (`:show`) | `log` |
| `writable_by` | upload, replace (`:create`, `:update`) | none |
| `deletable_by` | hide (`:destroy`) | none |

The defaults are restrictive on purpose.

| Entry | The viewer | For |
|---|---|---|
| `person` | is the subject | a person |
| `log` | may `:log` the subject | a person |
| `update` | may `:update` the subject | a person |
| `finance_audit`, `finance`, `finance_manage` | holds that finance tier or a higher one, as in force in the session (`doc/roles.md`, "The finance cap") | every subject |

- An entry that means nothing for the subject's kind, and one nobody knows,
  gives nobody access.
- Admins (the `admin` permission) may everything.
- A document that is not current (superseded, deleted) is read by who meets
  `readable_by` and may `:log` its subject; it is written and hidden only by
  admins. Without a known subject only admins see it.
- The lists of a new document come, unless given, from the document it
  replaces or from its original, else from its kind, else from the defaults.
  Only admins and the system give them: the upload form has tag selects for
  them for admins (`Wsjrdp::TagSelectHelper`; an empty one leaves the list
  to the kind); for anybody else lists in the request are ignored.

## Kinds of document

`wsjrdp_document_kinds` describes a kind of document per subject type and
`(key, secondary_key)` -- matched exactly, `""` for documents without a
secondary key. A document without a kind has the defaults and no
restrictions.

| Column | Meaning |
|---|---|
| `label`, `description`, `position` | name and order for pages |
| `readable_by`, `writable_by`, `deletable_by` | the lists a new document of the kind gets; a change reaches only new documents |
| `content_types` | MIME types an upload accepts, `type/*` as a wildcard; NULL: any |
| `extensions` | file name extensions an upload accepts; NULL: any; with `content_types` both must match |
| `max_upload_size_mb` | the upload limit of the kind; NULL: the general one |
| `people_column_name` | the column of `people` that holds the path of the kind's upload (`upload_*_pdf`, `generated_registration_pdf`); NULL for a kind without one, one kind per column |
| `role_rules` | the rules per contingent role, see below |
| `additional_info` | free JSON |

`role_rules` is a list of rules; for a person the first rule whose `roles`
contains the person's contingent role (`Person#short_payment_role`: `YP`,
`UL`, `IST`, `CMT`, `EXT`) applies, a rule without `roles` applies to all.
Keys of a rule, all optional:

| Key | Meaning |
|---|---|
| `roles` | contingent roles the rule is for |
| `offer_to` | entries (as in the lists) of who may pick the kind for an upload; absent or empty: not offered |
| `not_for_status` | statuses of the person in which the kind is not offered |
| `required` | `true`: the person must have the document |
| `missing_tag` | `{"tag", "from_status", "remove_on_upload"}`: the tag that marks the document missing from these statuses on, and whether an upload removes it |

The registration uploads (`contract`, `sepa`, `medical`, `photo_permission`,
`passport`, `data_agreement`, `recommendation`, `good_conduct`,
`registration_generated`) are kinds of `Person`, each with its column of
`people`: PDFs only, read by
`person` and `update` (`contract` and `sepa` also by `finance_audit`),
written and hidden by `log`; `registration_generated` is written only by the
system.

## Upload root and folders

The upload root is `Settings.documents.storage_root`, by default
`<wagon>/private/uploads` -- the root of the registration uploads, so the
paths of production work unchanged. A document keeps its path relative to
the root (`relative_storage_file_path`, unique) and the full path it was
written to (`absolute_storage_file_path`).

The folder of a person is `person/pdf/<id>/`, the folder of the registration
uploads. It holds files of every type, not only PDFs.

## File names

```
<YYYY-mm-dd-HH-MM-SS>[_<k>]--<subject_id>-<key>[-<n>][--<secondary_key>[-<m>]][~<derivation_key>][.<ext>]
```

| Part | Rule |
|---|---|
| timestamp | local time (`Time.zone`); a derivation has its own |
| `_<k>` | only when the name without it is taken; 1, 2, ... |
| `-<n>`, `-<m>` | `key_number`, `secondary_key_number`, only when above 0 |
| `--<secondary_key>[-<m>]` | when `secondary_key` is set or `m` is above 0; an empty secondary key with a number gives `<key>---<m>` |
| `~<derivation_key>` | for a derivation |
| `.<ext>` | see below; none when nothing gives one |

Examples (after `2026-10-11-14-03-07`):

```
--791-medical.pdf
--791-registration_generated.pdf
_1--791-deregistration-2--signed_form-3.pdf
--791-deregistration-2--signed_form-3~thumb_400.png
--791-medical---2.pdf
```

With only `key` set this is the name the registration uploads have. Every
name parses back (`DocumentFilename.parse`): keys contain no `-`, `.` or
`~`. A generated registration PDF is named with its key,
`registration_generated` (`RegistrationDocuments.generated_registration_filename`);
older ones keep their names with `registration-generated`, which the
registration scan reads as that key (`RegistrationDocuments::LEGACY_FILE_KEYS`).

The extension:

1. as given (the normal case): at most 20 characters of `a-z`, `0-9` and
   `.`, no `..`, no `.` at either end; anything else is refused;
2. else the longest run of known extensions (`DocumentFilename::EXTENSION_TYPES`)
   at the end of the uploaded file name, at most 20 characters --
   `Scan.final.v2.pdf.tar.gz` gives `pdf.tar.gz`;
3. else the extension of the content type Marcel finds in the file;
4. else none.

## Writing a file

`DocumentStore.store!(io, attributes, ext:)` stores one document; it is a
`DocumentWrite` (below) with one file. A document without `replaces` needs a
free slot, one with `replaces` needs that one to be still current.

1. builds the document; a block, if given, sees it before anything is written
   (the controller authorizes there);
2. copies the file into a temporary file `.tmp-<random>` in its folder; an
   upload above the limit of its kind, else
   `Settings.documents.max_upload_size_mb` (default 20), is refused -- only
   uploads have a limit;
3. records size, SHA-256, content type and `file_status` `present`; an upload
   whose type or extension its kind does not accept is refused;
4. under the lock of its slot: links the temporary file to its name; the link
   fails when the name is taken, which gives the next suffix. Where the file
   system has no hard links the file is created exclusively and filled. A row
   that cannot be saved because its path is taken also gives the next suffix,
   and the file is removed again;
5. saves the row (and supersedes the replaced document) and removes the
   temporary file.

`DocumentStore.register!(path, attributes)` records a file already under the
upload root in place (or as missing, when it is not there) and supersedes the
current document of its slot. `DocumentStore.hide!(document, reason:, by:)`
and `hide_current!(subject, reason:, by:, **slot)` hide a document, keeping
the file.

A file is never overwritten. A temporary file left by a crash stays, as does
a linked file whose transaction a crash cut off before its commit; the
checksum is not checked on download.

## Writing documents

`Wsjrdp2027::DocumentWrite` changes the documents of one subject, all of it
or nothing:

```ruby
write = Wsjrdp2027::DocumentWrite.new(subject: person, by: current_user, origin: "ui")
write.put(upload, {key: "contract", filename: upload.original_filename}, expected_current: id)
write.remove(key: "sepa", reason: "deleted_by_user")
write.on_subject { |person, results| person.status = "upload" }
results = write.commit!
```

- `put` stores a file as the new current document of its slot, `remove`
  hides the current one of a slot, `hide` hides one document -- also one
  whose subject is gone (no row lock, no people column then); `put`,
  `remove` and `on_subject` need the subject's record.
- `commit!` first prepares every file (steps 1-3 above). A refused file
  refuses the whole change before anything is written: one refused `put`
  raises its own error, several raise `DocumentWrite::Invalid` with the
  failures.
- Then, in one transaction under the locks of every slot it touches
  (`Wsjrdp::LockedChange`, `doc/wsjrdp/locked_change.md`), it reads each
  slot's current document anew, places the files (steps 4-5), hides what is
  removed, writes the path of each slot's current document into the people
  column of its kind (`people_column_name`; originals without numbers only),
  runs the `on_subject` block and saves the subject, which writes its
  PaperTrail version in the same transaction.
- Every `put` and `remove`, and a change with an `on_subject` block, locks
  the subject's row first, before the slots: what it reads of the subject --
  the columns of other slots, the status, the tags -- is not stale, two
  uploads into different slots of one person cannot both miss the other, and
  a subject being destroyed refuses the change (`RecordNotFound` once its row
  is gone, so no document of a destroyed subject is left behind current). A
  `hide` locks the row only when its kind has a people column.
- The files of a change that rolls back are removed again.
- `expected_current:` `:any` (default) follows whatever is current: the new
  document replaces it and takes its lists and refs unless the attributes
  give them, as a document built with `replaces` does (`DocumentStore#follow`);
  in a free slot it keeps the kind's lists. `nil` expects a free slot (else
  `slot_taken`); a document or id expects that one to be current (else
  `replaces_not_current`; for a removal `DocumentWrite::Conflict`).
- A file equal to the slot's current one (SHA-256) adds nothing: its result
  is `UNCHANGED`. `skip_unchanged: false` stores it anyway (`store!` does).
- Each result says `STORED`, `UNCHANGED`, `REMOVED` or `NOT_PRESENT`, with
  the document.
- An `on_subject` block stops the change with an error of its own
  (`Conflict`, `RecordInvalid`, ...), which `commit!` passes on; one that
  raises `ActiveRecord::Rollback` gets `DocumentWrite::RolledBack` from
  `commit!`. The change is undone either way, its files removed.
- `invalid_subject:` `:warn` (default) saves a subject that fails its
  validations without them, so that its people columns still name the files
  just written, and adds a message to `write.warnings`: an upload must not
  fail because other data of the person, as it lies in the database, is not
  valid. `DocumentStore.store!` logs the message. `:raise` lets such a
  subject stop the change.

Every change of the slots of `wsjrdp_documents` goes through `DocumentWrite`
or takes the lock of its slot as it does (`DocumentWrite.lock_key`:
`DocumentStore.register!` and the import of the registration uploads); only
then do the locks keep two writers apart, and only then do the people columns
stay in step. Two writers take no slot lock: the file check (`file_status`,
`file_checked_at`), which changes no slot, and the soft delete of a destroyed
person (`Person#soft_delete_wsjrdp_documents`), which marks every document of
the person deleted and locks the person's row first -- the order of a locked
change with that row, so the two never wait for each other in a circle.

## Download and upload

- `GET /documents/:id` sends the file. PDFs, PNG, JPEG, GIF, WebP and plain
  text go inline, everything else -- and everything with `?download=1` -- as
  an attachment; every answer has `Cache-Control: private, no-store` and
  `Content-Security-Policy: sandbox`. A missing file answers 404.
- `POST /documents` stores an upload from `wsjrdp/documents/_upload_form`
  (locals: `subject` and the keys, or `replaces`), with the author, a comment
  and the date of the document. A person whose data is not valid does not
  refuse it: the document and the people column of its kind are written, and
  the answer warns (`write.warnings`). While another write of the subject's
  documents holds their lock past the timeout (`Wsjrdp::LockedChange::Busy`),
  or the database ends the write in a deadlock, nothing is written and the
  answer asks to try again.

## JSON:API

`GET /api/documents?filter[subject_id]=<id>` lists the documents of people
the caller may read, `GET /api/documents/:id` shows one; both give the
metadata, not the file. The list needs `filter[subject_id]`, as reading is
checked document by document. An API key needs the scope `people:documents`
and an acting person (`doc/wsjrdp/service_tokens.md`).

## Document management

For admins (`:manage_documents`) in two places (`doc/navigation.md`,
section 9): the main section Dokumente with the tabs Alle, Nach Person und
Art and Arten, and Einstellungen → Dokumentenverwaltung with the tabs
Übersicht and Anmelde-Dokumente.

- **Übersicht** (`/document_management`, Einstellungen): the starting point;
  checks the files of all documents ("Missing files" above).
- **Alle** (`/documents`, main section Dokumente): every document, whatever its status, as an
  expandable table (`DocumentManagement::DocumentsColumns`,
  `DocumentManagement::DocumentsFilterSchema`) with quick filters for the
  status, a missing file and the origin. A row opens the document's page
  (`/documents/:id/details`): keys, file, lists, versions and derivations.
- **Nach Person und Art** (`/documents/by_person_and_kind`, main section
  Dokumente, `DocumentManagement::DocumentGroupsController`): one row per
  subject, key and secondary key -- a person's documents of one kind with
  all their versions, whatever their numbers
  (`DocumentManagement::DocumentGroups`) -- with the counts per status,
  missing files and the time span; derivations are left out. "aktuell"
  counts the combinations (key number and secondary key number) that have a
  current document, e.g. `1/2`, with an icon as quiet as the file status: a
  small grey tick for all, a yellow mark for some, a red one for none. Its
  filter is the one of the documents, applied before grouping. A row opens
  the group's page (`/documents/by_person_and_kind/:id`) as its detail: the
  counts, the versions (with their numbers when there are several
  combinations) with the comparison of two, and a link to them in Alle
  (filters `subject_id`, `key`, `secondary_key`; `_none` stands for no
  secondary key). The `:id` is the subject and the keys without numbers,
  `<subject_type>-<subject_id>-<key>[--<secondary_key>]`, e.g.
  `person-42-deregistration--signed_form`; `nil` for an empty type or id.
  Only the canonical form is accepted.
- **Anmelde-Dokumente** (`/document_management/registration_documents`,
  Einstellungen): registering the registration uploads, below.
- **Arten** (`/document_management/document_kinds`, main section
  Dokumente): the kinds of
  document ("Kinds of document") as an expandable table
  (`DocumentManagement::DocumentKindsColumns`): label and keys sharing one
  cell with a sortable header each (one block in the columns menu, each part
  hidden on its own; the subject type is a column shown on demand), the rights a line per right with the same lists
  sharing one, the accepted files as type families (the tooltip lists types
  and extensions), the first two role rules written out, the number of
  documents, and links to the kind's page (in this tab and in a new one). A row opens into the kind's form,
  which is also the kind's page (`/document_management/document_kinds/:id`);
  a save from a row goes back to the list as it was. The form gives the
  rights, the "offered to" entries, the content types and the extensions as
  tag selects (`Wsjrdp::TagSelectHelper`, TomSelect: the known entries with
  their meaning -- content types and extensions from Marcel, sent once per
  page as JSON --, other entries of the same form typed in). Above the
  content types and extensions, file kinds (`Wsjrdp2027::DocumentFileKinds`:
  PDF, Bilder, Word, ... -- label, icon and extensions, the types from
  Marcel) add or take out all their types and extensions at once and show
  whether all or a part of them is chosen; below the fields the form shows
  what the kind accepts and marks extensions and types that are never
  accepted (a type without a matching extension, or the other way round).
  The role rules come as
  one card per rule, in the order they apply: arrows move a card, "Regel
  hinzufügen" adds one, the bin removes one. `additional_info` is shown, not
  edited. The keys of a kind that documents have are fixed, and only a kind
  without documents can be deleted. A change of the rights reaches only new
  documents.

## Registration documents

The registration uploads -- the columns `people.upload_*_pdf` and
`generated_registration_pdf`, keys as their file names carry them
(`Wsjrdp2027::RegistrationDocuments::COLUMNS`) -- are registered as documents
where their files lie; nothing is moved, and `people` is never changed.

A **chain** is one person and one key: every file that column ever held,
oldest first (`RegistrationDocuments::Scan`). It is built from

- the PaperTrail versions of the person: when a path was set or the column
  emptied, and by whom (`whodunnit`);
- the column as it is now;
- the files in the person's folder whose name is `<timestamp>--<id>-<key>.pdf`;
- the rows already in `wsjrdp_documents`, by relative path.

A file no version names is placed by the time of its name. Registering a
chain (`RegistrationDocuments::Import`) writes one row per file, in order,
each replacing the one before (`replaces_id`):

| The file | Row |
|---|---|
| the column's | `current` |
| followed by another | `superseded`, `superseded_at` when the next was set |
| the last one after the column was emptied | `deleted`, `deleted_at` then, who emptied it in `additional_info.registration_upload.cleared_by` |
| not on disk | as above, with `file_status` `missing`, no size and no checksum |

`created_at` is when the file was set, `author` who set it, `origin`
`import`; `additional_info.registration_upload` names the column and the
source (`version`, `column`, `disk`). A present file gets its size, SHA-256
and content type. The lists are those of the key's kind
(`RegistrationDocuments.rights_for`), else the table's defaults.

Registering is repeatable: a registered row only changes its status (and
`file_status`), and files set since are appended to the chain. A chain is
`new` (nothing registered), `partial` or `complete` (every file registered as
the chain says).

The import reads and hashes a chain's files before it takes the lock of its
slot; under the lock it first checks that the chain's basis is as the scan
read it: the column, how many versions of
the person touch the columns, and the rows of the chain's files (none
changed, none new). A chain that changed since the scan is skipped
(`skipped` in the result), nothing of it written; the next run takes it as it
is by then.

The tab shows per key the people (chains) by state and the files, registered
and missing; the chains as an expandable table over the Array of chains,
with the CNF filter in Ruby (`DocumentManagement::RegistrationChainsFilterSchema`,
doc/wsjrdp/generic_filter_builder.md "Filtering arrays": person, person id,
key, state, counts; quick filters for the state and a missing file), each with
its files as detail; and what the scan cannot place (a file with another
name, a folder without a person, ...). Files of documents stored otherwise in
the same folder are left alone.

- **Ausgewählte registrieren** registers the chosen chains -- across pages,
  or with "alle Seiten" every chain of the filter. Up to 200 chains at once,
  more in the background.
- **Alle registrieren** registers every chain not `complete` in the
  background (`Wsjrdp2027::RegisterDocumentsJob`).

The tab shows the rights the new rows get per key, read only; they are
changed in the tab Arten. A run in the background is a tracked job
(`Wsjrdp::TrackedJob`, `doc/wsjrdp/tracked_jobs.md`): it is queued with its
`HitobitoLogEntry` (category `documents`, `sub_category`
`registration_documents_sync`, `RegisterDocumentsJob.entries`; also under
Einstellungen → Hitobito Log), which it takes over as it starts and keeps up
to date while it works -- the phase (`scan`, `register`), the totals of
people, chains and files and how many of them are done. The tab's progress
display (`shared/wsjrdp/_tracked_job_progress`) shows people and files,
asks `/document_management/registration_documents/progress` and cancels
through `/document_management/registration_documents/cancel`; a run stops
after the chain at hand -- each chain is registered in a transaction of its
own, so nothing is left half done, and registering again carries on from
there. A run over all chains notes the files of the chains it leaves as
they stand as checked (`Import#checked`: a thousand rows per statement,
leaving out a row someone writes at that moment). The entry ends with the counts
(chains, created, updated, failed, skipped), the errors and the timing.

`RegistrationDocuments.record!(person, people_column:, path:, author:,
origin:)` keeps `wsjrdp_documents` in step when a column is set: it
registers the column's file in place (`DocumentStore.register!`) as the
current document of its key, with `additional_info.registration_upload`
(column, source), and supersedes the one before; a path registered already
answers its row. `RegistrationDocuments.clear!(person, people_column:, by:)`
hides the current document of an emptied column. `key_for` and
`people_column_for` map columns and keys.
