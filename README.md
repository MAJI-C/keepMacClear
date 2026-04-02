# keepMacClear

Utilities to help keep a macOS machine tidy (cache/log cleanup and related housekeeping).

## User

### What it does
- Cleans up common macOS “safe to remove” clutter (e.g., app caches, derived build artifacts) based on what you enable.
- Aims to be conservative: you choose what to delete, and you can dry-run first.

### Requirements
- macOS
- (Optional) Xcode, if you want Xcode-related cleanup (e.g., `DerivedData`)

### Install
Clone or download this folder onto your Mac.

### Run
Add the exact run command(s) your project supports here.

Examples (replace with your actual commands):

```bash
# dry run (no changes)
./keepMacClear --dry-run

# run cleanup
./keepMacClear
```

### Configuration
Document any config file(s) and defaults here.

Common patterns:
- Environment variables
- A config file (e.g., `keepMacClear.yml`)
- CLI flags

### Safety notes
- Prefer running with a dry-run option first.
- Make sure you understand each cleanup target before enabling it.
- Don’t run as `root` unless you explicitly need to.

### Troubleshooting
- **Permission errors**: run from a user account with access to the target directories; avoid `sudo` unless required.
- **Nothing happens**: verify paths exist on your machine; check any include/exclude lists.
- **Xcode still large**: ensure `DerivedData` cleanup is enabled (and Xcode is closed).

## Maintainer

### Repository layout
Describe the key folders/files here once they exist.

### Development
Add the exact developer workflow here (replace with your actual commands):

```bash
# run locally
./keepMacClear --dry-run

# format/lint (if applicable)
# <your command>

# tests (if applicable)
# <your command>
```

### Release checklist
- Update `README.md` usage examples to match the current CLI/API.
- Verify dry-run mode output is accurate.
- Run any tests/lints.
- Tag the release and attach artifacts (if you ship a binary/script).

### Support policy
- Specify which macOS versions you support.
- Specify whether you accept feature requests vs bug reports.

## Maintainer contact
- Name: MJ (replace if needed)
- Preferred contact: (add email/GitHub)

## License
Add a license (MIT/Apache-2.0/etc) or link to `LICENSE`.
