# Birthday Card Generator for Anki

![Cake image](./AnkiBirthdays.iconset/icon_256x256.png "Cake image")

A macOS application that generates Anki flashcards from the birthdays in your Apple Contacts. The app creates a tab-separated values (TSV) file that can be imported directly into Anki to help you remember your friends' and family's birthdays.

## Features

- Extracts birthday information from Apple Contacts
- Generates Anki-compatible flashcards in the format "When is [Name]'s birthday?" → "[Date]"
- Native macOS GUI with progress tracking

## Requirements

- macOS 11.0 or later
- Permission to access your Contacts (the app will prompt for this)
- Anki (for importing the generated cards)

## Development

### Building without Nix

1. Install Zig 0.14.1 from [ziglang.org](https://ziglang.org/download/)
2. Clone this repository
3. Build the application:
   ```bash
   zig build
   ```
4. Run the application:
   ```bash
   ./zig-out/bin/bdays
   ```

### Building with Nix (Recommended for reproducible builds)

1. Install Nix with flakes support
2. Clone this repository
3. Enter the development environment:
   ```bash
   nix develop --impure
   ```
   The `--impure` flag is required to access macOS system frameworks.
4. Build the application:
   ```bash
   zig build
   ```
5. Run the application:
   ```bash
   ./zig-out/bin/bdays
   ```

Alternatively, you can build directly without entering the shell:
```bash
nix develop --impure -c zig build
```

### Debug Mode

To see detailed output during card generation, run with the `--debug` flag:
```bash
./zig-out/bin/bdays --debug
```

### Creating a Release

To create a distributable DMG installer:

1. Ensure you have `create-dmg` installed:
   ```bash
   brew install create-dmg
   ```

2. Run the release script:
   ```bash
   ./release.sh
   ```

3. When prompted, enter the version number (e.g., `1.2`, `2.0`, etc.)

The script will:
- Update the app bundle's version information
- Build the latest code
- Copy the binary to the app bundle
- Create a DMG installer named `AnkiBirthdays-[VERSION].dmg`

## Usage

1. Launch the application
2. Click "Generate Cards" to create flashcards from your contacts
3. The app will request permission to access your Contacts if needed
4. Choose a location to save the output file (optional - defaults to Downloads)
5. Import the generated TSV file into Anki:
   - In Anki: File → Import
   - Select the generated file
   - Set field separator to "Tab"
   - Import the cards

## Architecture

The application is built in Zig and uses:
- Objective-C runtime for macOS GUI integration
- Cocoa frameworks (Foundation, AppKit) for native UI
- AppleScript for accessing Contacts data
- Multi-threaded architecture with progress reporting

The codebase is modularized into:
- `main.zig` - Application entry point and shared state
- `src/objc_helpers.zig` - Objective-C runtime utilities
- `src/ui_components.zig` - GUI component creation
- `src/app_delegate.zig` - Application event handling
- `src/threading.zig` - Thread management and UI updates
- `src/file_operations.zig` - File system operations
- `src/anki_generator.zig` - Core card generation logic

## License

See [LICENSE.md](LICENSE.md) for details.
