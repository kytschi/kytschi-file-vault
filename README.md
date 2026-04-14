# Kytschi's File Vault

A desktop file file cataloguing application built with D and DQt (Qt6 bindings).

**Note this started as an AI build experiment. I used it to initial kick the project off then I ended up just building on top of it for a friend. Has been an interesting experience.**

## Features

- **File Management**: Add individual files or entire folders to your file vault
- **Custom Categories**: Create user-defined categories (Books, Music, Videos, Websites, etc.)
- **Tagging**: Tag files with one or more categories for flexible organization
- **Search**: Full-text search across file names, paths, extensions, and metadata
- **File Information**: View detailed file info including name, path, type, size, date added, categories, and custom metadata
- **Metadata Editing**: Add custom metadata notes to any file
- **Category Filtering**: Browse files by category or view all files at once
- **SQLite Database**: All file references and metadata stored locally in `.kytschi_file_vault.db`

## Prerequisites

- **D Compiler** (dmd v2.103+)
- **DUB** (D package manager)
- **Qt 6.4.2+** libraries installed
- **SQLite3** development library (`libsqlite3-dev` on Debian/Ubuntu)

## Building

### Linux

```bash
# Install dependencies (Debian/Ubuntu)
sudo apt install libsqlite3-dev qt6-base-dev

# Build and run
dub run
```

### Windows

```cmd
@set DFLAGS="-L/LIBPATH:C:\Qt\6.4.2\msvc2019_64\lib"
@set PATH=C:\Qt\6.4.2\msvc2019_64\bin;%PATH%
dub run --compiler=dmd --arch=x86_64 --build-mode=allAtOnce
```

## Usage

1. **Add files**: Use `File > Add File...` or `File > Add Folder...` to add media to the vault
2. **Create categories**: Click the `+` button in the Categories panel to define categories
3. **Tag files**: Select a file, then use `Edit > Tag File...` to assign it to a category
4. **Search**: Type in the search bar and click "search" or press Enter
5. **Browse by category**: Click a category in the left panel to filter files
6. **View file info**: Click any file tile to see its details in the right panel
7. **Edit metadata**: Select a file, then use `Edit > Edit Metadata...` to add notes

## Project Structure

```
source/
├── app.d        # Main application, UI layout, event handling
└── database.d   # SQLite database layer (files, categories, tagging)
```

## License

See LICENSE file.
