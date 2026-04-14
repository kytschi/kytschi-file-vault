module database;

// SQLite3 C bindings
extern(C)
{
    enum SQLITE_OK = 0;
    enum SQLITE_ROW = 100;
    enum SQLITE_DONE = 101;
    enum SQLITE_OPEN_READWRITE = 0x00000002;
    enum SQLITE_OPEN_CREATE = 0x00000004;

    alias sqlite3 = void;
    alias sqlite3_stmt = void;

    int sqlite3_open_v2(const char* filename, sqlite3** ppDb, int flags, const char* zVfs);
    int sqlite3_close(sqlite3*);
    int sqlite3_exec(sqlite3*, const char* sql, int function(void*, int, char**, char**) callback, void* arg, char** errmsg);
    void sqlite3_free(void*);
    int sqlite3_prepare_v2(sqlite3* db, const char* zSql, int nByte, sqlite3_stmt** ppStmt, const char** pzTail);
    int sqlite3_step(sqlite3_stmt*);
    int sqlite3_finalize(sqlite3_stmt*);
    int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int, void function(void*));
    int sqlite3_bind_int(sqlite3_stmt*, int, int);
    int sqlite3_bind_int64(sqlite3_stmt*, int, long);
    long sqlite3_last_insert_rowid(sqlite3*);
    const(char)* sqlite3_column_text(sqlite3_stmt*, int iCol);
    int sqlite3_column_int(sqlite3_stmt*, int iCol);
    long sqlite3_column_int64(sqlite3_stmt*, int iCol);
    int sqlite3_column_count(sqlite3_stmt*);
    const(char)* sqlite3_errmsg(sqlite3*);

    enum SQLITE_TRANSIENT = cast(void function(void*))-1;
}

struct StoredFile
{
    long id;
    string entry_path;
    string entry_name;
    string entry_extension;
    string entry_type;
    long entry_size;
    string created_at;
    string updated_at;
    string metadata;
}

struct Category
{
    long id;
    string name;
}

class Database
{
    private sqlite3* db;

    bool open(string path)
    {
        import std.string : toStringz;

        int rc = sqlite3_open_v2(
            path.toStringz(),
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, null
        );

        if (rc != SQLITE_OK) {
            return false;
        }

        createTables();
        return true;
    }

    void close()
    {
        if (db !is null) {
            sqlite3_close(db);
            db = null;
        }
    }

    private void createTables()
    {
        string sql = "
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                entry_path TEXT NOT NULL,
                entry_name TEXT NOT NULL,
                entry_extension TEXT,
                entry_type TEXT,
                entry_size INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now','localtime')),
                updated_at TEXT DEFAULT (datetime('now','localtime')),
                metadata TEXT DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE
            );

            CREATE TABLE IF NOT EXISTS entry_categories (
                entry_id INTEGER NOT NULL,
                category_id INTEGER NOT NULL,
                PRIMARY KEY (entry_id, category_id),
                FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
            );
        ";
        execSQL(sql);
    }

    private void execSQL(string sql)
    {
        import std.string : toStringz;
        char* errmsg;
        int rc = sqlite3_exec(db, sql.toStringz(), null, null, &errmsg);
        if (rc != SQLITE_OK && errmsg !is null)
        {
            sqlite3_free(errmsg);
        }
    }

    long addEntry(string entry_path, string entry_name, string entry_extension, string entry_type, long entry_size, string metadata)
    {
        import std.string : toStringz;
        string sql = "INSERT INTO entries (entry_path, entry_name, entry_extension, entry_type, entry_size, metadata) VALUES (?, ?, ?, ?, ?, ?)";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return -1;

        sqlite3_bind_text(stmt, 1, entry_path.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, entry_name.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, entry_extension.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, entry_type.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 5, entry_size);
        sqlite3_bind_text(stmt, 6, metadata.toStringz(), -1, SQLITE_TRANSIENT);

        int rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE)
            return -1;

        return sqlite3_last_insert_rowid(db);
    }

    void removeEntry(long entry_id)
    {
        import std.string : toStringz;
        // Remove category associations first
        string sql1 = "DELETE FROM entry_categories WHERE entry_id = ?";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql1.toStringz(), -1, &stmt, null) == SQLITE_OK)
        {
            sqlite3_bind_int64(stmt, 1, entry_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        string sql2 = "DELETE FROM entries WHERE id = ?";
        if (sqlite3_prepare_v2(db, sql2.toStringz(), -1, &stmt, null) == SQLITE_OK)
        {
            sqlite3_bind_int64(stmt, 1, entry_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }

    StoredFile[] getAllEntries()
    {
        return queryEntries("SELECT * FROM entries ORDER BY entry_name COLLATE NOCASE ASC");
    }

    StoredFile[] getEntriesByCategory(long category_id)
    {
        import std.string : toStringz;
        string sql = "SELECT m.* FROM entries m " ~
                     "INNER JOIN entry_categories fc ON m.id = fc.entry_id " ~
                     "WHERE fc.category_id = ? ORDER BY m.entry_name COLLATE NOCASE ASC";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return [];

        sqlite3_bind_int64(stmt, 1, category_id);
        return collectEntries(stmt);
    }

    StoredFile[] searchEntries(string query)
    {
        import std.string : toStringz;
        string sql = "SELECT * FROM entries WHERE " ~
                     "entry_name LIKE ? OR " ~
                     "entry_extension LIKE ? OR metadata LIKE ? " ~
                     "ORDER BY entry_name COLLATE NOCASE ASC";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return [];

        string pattern = "%" ~ query ~ "%";
        sqlite3_bind_text(stmt, 1, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        return collectEntries(stmt);
    }

    StoredFile[] searchEntriesInCategory(string query, long category_id)
    {
        import std.string : toStringz;
        string sql = "SELECT m.* FROM entries m " ~
                     "INNER JOIN entry_categories fc ON m.id = fc.entry_id " ~
                     "WHERE fc.category_id = ? AND (" ~
                     "m.entry_name LIKE ? OR " ~
                     "m.entry_extension LIKE ? OR m.metadata LIKE ?) " ~
                     "ORDER BY m.entry_name COLLATE NOCASE ASC";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return [];

        string pattern = "%" ~ query ~ "%";
        sqlite3_bind_int64(stmt, 1, category_id);
        sqlite3_bind_text(stmt, 2, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 6, pattern.toStringz(), -1, SQLITE_TRANSIENT);
        return collectEntries(stmt);
    }

    StoredFile getEntryById(long entry_id)
    {
        import std.string : toStringz;
        string sql = "SELECT * FROM entries WHERE id = ?";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK) {
            return StoredFile.init;
        }

        sqlite3_bind_int64(stmt, 1, entry_id);
        auto files = collectEntries(stmt);
        if (files.length > 0) {
            return files[0];
        }
        return StoredFile.init;
    }

    private StoredFile[] queryEntries(string sql)
    {
        import std.string : toStringz;
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return [];
        return collectEntries(stmt);
    }

    private StoredFile[] collectEntries(sqlite3_stmt* stmt)
    {
        StoredFile[] results;
        while (sqlite3_step(stmt) == SQLITE_ROW)
        {
            StoredFile f;
            f.id = sqlite3_column_int64(stmt, 0);
            f.entry_path = columnText(stmt, 1);
            f.entry_name = columnText(stmt, 2);
            f.entry_extension = columnText(stmt, 3);
            f.entry_type = columnText(stmt, 4);
            f.entry_size = sqlite3_column_int64(stmt, 5);
            f.created_at = columnText(stmt, 6);
            f.updated_at = columnText(stmt, 7);
            f.metadata = columnText(stmt, 8);
            results ~= f;
        }
        sqlite3_finalize(stmt);
        return results;
    }

    long addCategory(string name)
    {
        import std.string : toStringz;
        string sql = "INSERT OR IGNORE INTO categories (name) VALUES (?)";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return -1;

        sqlite3_bind_text(stmt, 1, name.toStringz(), -1, SQLITE_TRANSIENT);
        int rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE)
            return -1;

        return sqlite3_last_insert_rowid(db);
    }

    void removeCategory(long category_id)
    {
        import std.string : toStringz;
        string sql1 = "DELETE FROM entry_categories WHERE category_id = ?";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql1.toStringz(), -1, &stmt, null) == SQLITE_OK)
        {
            sqlite3_bind_int64(stmt, 1, category_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }

        string sql2 = "DELETE FROM categories WHERE id = ?";
        if (sqlite3_prepare_v2(db, sql2.toStringz(), -1, &stmt, null) == SQLITE_OK)
        {
            sqlite3_bind_int64(stmt, 1, category_id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }

    Category[] getAllCategories()
    {
        import std.string : toStringz;
        Category[] results;
        string sql = "SELECT id, name FROM categories ORDER BY name COLLATE NOCASE ASC";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return results;

        while (sqlite3_step(stmt) == SQLITE_ROW)
        {
            Category c;
            c.id = sqlite3_column_int64(stmt, 0);
            c.name = columnText(stmt, 1);
            results ~= c;
        }
        sqlite3_finalize(stmt);
        return results;
    }

    void tagEntry(long entry_id, long category_id)
    {
        import std.string : toStringz;
        string sql = "INSERT OR IGNORE INTO entry_categories (entry_id, category_id) VALUES (?, ?)";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return;

        sqlite3_bind_int64(stmt, 1, entry_id);
        sqlite3_bind_int64(stmt, 2, category_id);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    void untagEntry(long entry_id, long category_id)
    {
        import std.string : toStringz;
        string sql = "DELETE FROM entry_categories WHERE entry_id = ? AND category_id = ?";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return;

        sqlite3_bind_int64(stmt, 1, entry_id);
        sqlite3_bind_int64(stmt, 2, category_id);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    Category[] getCategoriesForEntry(long entry_id)
    {
        import std.string : toStringz;
        Category[] results;
        string sql = "SELECT c.id, c.name FROM categories c " ~
                     "INNER JOIN entry_categories fc ON c.id = fc.category_id " ~
                     "WHERE fc.entry_id = ? ORDER BY c.name COLLATE NOCASE ASC";
        sqlite3_stmt* stmt;
        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK)
            return results;

        sqlite3_bind_int64(stmt, 1, entry_id);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            Category c;
            c.id = sqlite3_column_int64(stmt, 0);
            c.name = columnText(stmt, 1);
            results ~= c;
        }
        sqlite3_finalize(stmt);
        return results;
    }

    bool updateEntry(long entry_id, string name, string metadata)
    {
        import std.string : toStringz;

        string sql = "UPDATE entries SET entry_name = ?, metadata = ? WHERE id = ?";
        sqlite3_stmt* stmt;

        if (sqlite3_prepare_v2(db, sql.toStringz(), -1, &stmt, null) != SQLITE_OK) {
            return false;
        }

        sqlite3_bind_text(stmt, 1, name.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, metadata.toStringz(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 3, entry_id);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        return true;
    }

    private string columnText(sqlite3_stmt* stmt, int col)
    {
        const(char)* text = sqlite3_column_text(stmt, col);
        if (text is null)
            return "";
        // Copy the string to D-managed memory
        import core.stdc.string : strlen;
        size_t len = strlen(text);
        char[] buf = new char[len];
        buf[] = text[0 .. len];
        return cast(string)buf;
    }
}
