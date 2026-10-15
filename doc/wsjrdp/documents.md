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
`~`.

The extension:

1. as given (the normal case): at most 20 characters of `a-z`, `0-9` and
   `.`, no `..`, no `.` at either end; anything else is refused;
2. else the longest run of known extensions (`DocumentFilename::EXTENSION_TYPES`)
   at the end of the uploaded file name, at most 20 characters --
   `Scan.final.v2.pdf.tar.gz` gives `pdf.tar.gz`;
3. else the extension of the content type Marcel finds in the file;
4. else none.

## Writing a file

`DocumentStore.store!(io, attributes, ext:)`:

1. builds the document; a block, if given, sees it before anything is written
   (the controller authorizes there);
2. copies the file into a temporary file `.tmp-<random>` in its folder; an
   upload above the limit of its kind, else
   `Settings.documents.max_upload_size_mb` (default 20), is refused -- only
   uploads have a limit;
3. records size, SHA-256, content type and `file_status` `present`; an upload
   whose type or extension its kind does not accept is refused;
4. links the temporary file to its name; the link fails when the name is
   taken, which gives the next suffix. Where the file system has no hard
   links the file is created exclusively and filled. A row that cannot be
   saved because its path is taken also gives the next suffix, and the file
   is removed again;
5. saves the row (and supersedes the replaced document) and removes the
   temporary file.

`DocumentStore.register!(path, attributes)` records a file already under the
upload root in place (or as missing, when it is not there) and supersedes the
current document of its slot. `DocumentStore.hide!(document, reason:, by:)`
and `hide_current!(subject, reason:, by:, **slot)` hide a document, keeping
the file.

A file is never overwritten. A file whose row an enclosing transaction rolls
back later stays without a row, as does a temporary file after a crash; the
checksum is not checked on download.

## Download and upload

- `GET /documents/:id` sends the file. PDFs, PNG, JPEG, GIF, WebP and plain
  text go inline, everything else -- and everything with `?download=1` -- as
  an attachment; every answer has `Cache-Control: private, no-store` and
  `Content-Security-Policy: sandbox`. A missing file answers 404.
- `POST /documents` stores an upload from `wsjrdp/documents/_upload_form`
  (locals: `subject` and the keys, or `replaces`), with the author, a comment
  and the date of the document.

## JSON:API

`GET /api/documents?filter[subject_id]=<id>` lists the documents of people
the caller may read, `GET /api/documents/:id` shows one; both give the
metadata, not the file. The list needs `filter[subject_id]`, as reading is
checked document by document. An API key needs the scope `people:documents`
and an acting person (`doc/wsjrdp/service_tokens.md`).
