/**
 * Kytschi's file vault
 *
 * @author 		Mike Welsh
 * @copyright   2026 Mike Welsh
 * @version     0.0.1 Alpha
 *
*/
module app;

import core.runtime;
import core.stdcpp.new_;
import std.conv;
import std.stdio;
import std.path : baseName, extension;
import std.file : getSize;
import std.datetime;
import std.string;

import qt.config;
import qt.helpers;
import qt.core.object;
import qt.core.string;
import qt.core.stringlist;
import qt.core.size;
import qt.core.namespace;
import qt.core.flags;
import qt.core.variant;
import qt.core.url;
import qt.gui.cursor;
import qt.gui.desktopservices;
import qt.gui.icon;
import qt.widgets.application;
import qt.widgets.boxlayout;
import qt.widgets.label;
import qt.widgets.pushbutton;
import qt.widgets.widget;
import qt.widgets.mainwindow;
import qt.widgets.menubar;
import qt.widgets.menu;
import qt.widgets.action;
import qt.widgets.statusbar;
import qt.widgets.lineedit;
import qt.widgets.listwidget;
import qt.widgets.scrollarea;
import qt.widgets.gridlayout;
import qt.widgets.frame;
import qt.widgets.messagebox;
import qt.widgets.filedialog;
import qt.widgets.inputdialog;
import qt.widgets.textedit;
import qt.widgets.sizepolicy;
import qt.gui.font;

import database;

// Global app instance for delegate captures
__gshared FileVaultApp gApp;

class FileVaultApp
{
    private QMainWindow main_window;
    private Database db;
    private QWidget file_grid_container;
    private QWidget name_panel;
    private QGridLayout file_grid_layout;
    private QListWidget category_list;
    private QLineEdit name_input;
    private QTextEdit name_meta;
    private QLineEdit search_input;
    private QLabel file_info_label;
    private QPushButton btn_clear_search;
    private QPushButton btn_open_file;
    private QPushButton btn_save_file;
    private QPushButton btn_tag_file;
    private QLabel status_bar_date;
    private QLabel current_category_label;
    private long selected_category_id = -1;
    private long selected_entry_id = -1;
    private StoredFile selected_entry;
    private QWidget selection_entry = null;
    private int cols = 16;
    private string app_version = "0.0.1 Alpha";

    // Keep references to prevent GC collection of delegate closures
    private Object[] _prevent_gc;

    void initialize()
    {
        db = new Database();
        string dbPath = getDbPath();
        if (!db.open(dbPath)) {
            return;
        }

        main_window = cpp_new!QMainWindow();
        main_window.setWindowTitle(QString("Kytschi's File Vault"));
        //main_window.resize(1500, 800);

        // Style: red header bar simulated via menu bar background
        main_window.setStyleSheet(QString(
            "QMainWindow { background-color: #ffffff; color: #333;}
            QMenuBar { background-color: #e74c3c; color: white; padding: 4px; font-weight: bold; }
            QMenuBar::item { background-color: transparent; padding: 4px 8px; }
            QMenuBar::item:selected { background-color: #c0392b; }
            QStatusBar { background-color: #f0f0f0; border-top: 1px solid #cccccc; }"
        ));

        setupMenuBar();
        setupCentralWidget();
        setupStatusBar();
        refreshCategories();
        refreshFileGrid();
    }

    private string getDbPath()
    {
        import std.path : buildPath, expandTilde;
        //return buildPath(expandTilde("~"), ".kytschi_file_vault.db");
        return ".kytschi_file_vault.db";
    }

    private void setupMenuBar()
    {
        auto menuBar = main_window.menuBar();

        // File menu
        auto fileMenu = menuBar.addMenu(QString("File"));

        auto addEntryAction = fileMenu.addAction(QString("Add File"));
        QObject.connect(addEntryAction.signal!"triggered", main_window, delegate void() {
            gApp.doAddFile();
        });

        auto addFolderAction = fileMenu.addAction(QString("Add Folder"));
        QObject.connect(addFolderAction.signal!"triggered", main_window, delegate void() {
            gApp.doAddFolder();
        });

        auto addUrlAction = fileMenu.addAction(QString("Add URL"));
        QObject.connect(addUrlAction.signal!"triggered", main_window, delegate void() {
            gApp.doAddUrl();
        });

        fileMenu.addSeparator();

        auto exitAction = fileMenu.addAction(QString("Exit"));
        QObject.connect(exitAction.signal!"triggered", main_window.slot!"close");

        // Edit menu
        auto editMenu = menuBar.addMenu(QString("Edit"));

        auto removeEntryAction = editMenu.addAction(QString("Remove Selected Entry"));
        QObject.connect(removeEntryAction.signal!"triggered", main_window, delegate void() {
            gApp.doRemoveFile();
        });

        auto removeCatAction = editMenu.addAction(QString("Remove Selected Category"));
        QObject.connect(removeCatAction.signal!"triggered", main_window, delegate void() {
            gApp.doRemoveCategory();
        });

        auto tagEntryAction = editMenu.addAction(QString("Tag The Entry"));
        QObject.connect(tagEntryAction.signal!"triggered", main_window, delegate void() {
            gApp.doTagFile();
        });

        // Help menu
        auto helpMenu = menuBar.addMenu(QString("Help"));
        auto aboutAction = helpMenu.addAction(QString("About"));
        QObject.connect(aboutAction.signal!"triggered", main_window, delegate void() {
            QMessageBox.about(
                gApp.main_window,
                QString("About"),
                QString("Kytschi's File Vault\n\nA cataloguing application designed to help organise your files and websites with custom categories.\n\nVersion: " ~ app_version)
            );
        });
    }

    private void setupCentralWidget()
    {
        auto central_widget = cpp_new!QWidget(main_window);
        central_widget.setObjectName("central_widget");
        central_widget.setStyleSheet(QString(
            "QWidget#central_widget { background-color: #ffffff; }"
        ));
        main_window.setCentralWidget(central_widget);

        auto main_layout = cpp_new!QHBoxLayout(central_widget);
        main_layout.setContentsMargins(0, 0, 0, 0);
        main_layout.setSpacing(0);

        auto left_panel = cpp_new!QWidget(central_widget);
        left_panel.setObjectName("left_panel");
        left_panel.setStyleSheet(QString(
            "QWidget#left_panel { background-color: #ffffff; border-right: 1px solid #cccccc; }"
        ));
        left_panel.setFixedWidth(140);

        auto left_layout = cpp_new!QVBoxLayout(left_panel);
        left_layout.setContentsMargins(0, 0, 0, 0);
        left_layout.setSpacing(0);

        // Categories header with + button
        auto cat_header = cpp_new!QWidget(left_panel);
        auto cat_header_layout = cpp_new!QHBoxLayout(cat_header);
        cat_header_layout.setContentsMargins(4, 4, 4, 4);

        auto cat_label = cpp_new!QLabel(cat_header);
        cat_label.setText(QString("Categories"));
        cat_label.setObjectName("cat_label");
        cat_label.setStyleSheet(QString(
            "QLabel#cat_label { padding: 5px 4px 6px 4px; }"
        ));
        auto cat_font = cast(qt.gui.font.QFont)cat_label.font();
        cat_font.setBold(true);
        cat_label.setFont(cat_font);
        cat_header_layout.addWidget(cat_label);

        auto btn_add_cat = cpp_new!QPushButton(cat_header);
        btn_add_cat.setText(QString("+"));
        btn_add_cat.setFixedSize(QSize(24, 24));
        btn_add_cat.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        QObject.connect(btn_add_cat.signal!"clicked", main_window, delegate void() {
            gApp.doAddCategory();
        });
        cat_header_layout.addWidget(btn_add_cat);

        left_layout.addWidget(cat_header);

        // Category list
        category_list = cpp_new!QListWidget(left_panel);
        category_list.setStyleSheet(QString(
            "QListWidget {
                border: none;
                border-top: 1px solid #cccccc;
                background-color: #ffffff;
                outline: 0;
                font-weight: normal;
            }
            QListWidget::item { 
                padding: 6px 8px;
                border: none;
                font-weight: normal;
            }
            QListWidget::item:selected { 
                background-color: #e0e0e0;
                color: #000;
                border: 1px solid #ccc;
                font-weight: bold;
            }
            QLineEdit { 
                padding: 4px 8px;
                border: 1px solid #cccccc; 
                background: #ffffff;
                text-align: left;
            }"
        ));
        category_list.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        QObject.connect(category_list.signal!"currentRowChanged", main_window, delegate void(int row) {
            gApp.doCategoryChanged(row);
        });
        left_layout.addWidget(category_list);

        main_layout.addWidget(left_panel);

        // === Center: Search + File grid ===
        auto center_panel = cpp_new!QWidget(central_widget);
        center_panel.setObjectName("center_panel");
        center_panel.setStyleSheet(QString(
            "QWidget#center_panel {
                background-color: #ffffff;
                border-left: 1px solid #cccccc;
            }
            QPushButton {
                background-color: #ffffff;
                border: none;
                text-align: bottom;
            } 
            QPushButton:hover {
                background-color: #e8f0fe;
                border: 1px solid #4285f4;
            }
            QWidget[selected=\"true\"] {
                border: 1px solid #3498db;
            }
            QWidget[selected=\"false\"] {
                border: none;
            }"
        ));
        center_panel.setObjectName("center_panel");
        
        auto center_layout = cpp_new!QVBoxLayout(center_panel);
        center_layout.setContentsMargins(1, 0, 0, 0);
        center_layout.setSpacing(0);

        // Search bar
        auto search_bar = cpp_new!QWidget(center_panel);
        auto search_layout = cpp_new!QHBoxLayout(search_bar);
        search_layout.setContentsMargins(8, 4, 8, 4);

        search_input = cpp_new!QLineEdit(search_bar);
        search_input.setPlaceholderText(QString("Search your files"));
        search_input.setStyleSheet(QString(
            ""
        ));
        search_layout.addWidget(search_input);

        btn_clear_search = cpp_new!QPushButton(search_bar);
        btn_clear_search.hide();
        btn_clear_search.setObjectName("btn_clear_search");
        btn_clear_search.setText(QString("clear"));
        btn_clear_search.setStyleSheet(QString(
            "QPushButton#btn_clear_search {
                background-color: #e8e8e8;
                padding: 4px 16px;
                border: 1px solid #cccccc;
            }"
        ));
        btn_clear_search.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        QObject.connect(btn_clear_search.signal!"clicked", main_window, delegate void() {
            search_input.setText("");
            btn_clear_search.hide();
            gApp.refreshFileGrid();
        });
        search_layout.addWidget(btn_clear_search);

        auto btn_search = cpp_new!QPushButton(search_bar);
        btn_search.setObjectName("btn_search");
        btn_search.setText(QString("search"));
        btn_search.setStyleSheet(QString(
            "QPushButton#btn_search {
                background-color: #e8e8e8;
                padding: 4px 16px;
                border: 1px solid #cccccc;
            }"
        ));
        btn_search.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        QObject.connect(btn_search.signal!"clicked", main_window, delegate void() {
            gApp.refreshFileGrid();
        });
        search_layout.addWidget(btn_search);

        // Also search on Enter key
        QObject.connect(search_input.signal!"returnPressed", main_window, delegate void() {
            gApp.refreshFileGrid();
        });

        center_layout.addWidget(search_bar);

        // Current category label
        current_category_label = cpp_new!QLabel(center_panel);
        current_category_label.setObjectName("current_category_label");
        current_category_label.setText(QString("All"));
        auto label_font = cast(qt.gui.font.QFont)current_category_label.font();
        label_font.setBold(true);
        current_category_label.setFont(label_font);
        current_category_label.setStyleSheet(QString(
            "QLabel#current_category_label { 
                padding: 5px 8px;
                background-color: #f0f0f0;
                border-bottom: 1px solid #cccccc;
                border-top: 1px solid #cccccc;
            }"
        ));
        center_layout.addWidget(current_category_label);

        // Scrollable file grid
        auto scroll_area = cpp_new!QScrollArea(center_panel);
        scroll_area.setObjectName("scroll_area");
        scroll_area.setWidgetResizable(true);
        scroll_area.setStyleSheet(QString(
            "QScrollArea#scroll_area { 
                background-color: #ffffff; 
                border: none;
            }"
        ));

        file_grid_container = cpp_new!QWidget();
        file_grid_container.setObjectName("file_grid_container");
        file_grid_container.setStyleSheet(QString(
            "QWidget#file_grid_container {
                background-color: #ffffff;
                border: none;
            }
            QWidget#file_grid_layout { 
                background-color: #ffffff;
                border: none;
            }"
        ));

        file_grid_layout = cpp_new!QGridLayout(file_grid_container);
        file_grid_layout.setObjectName("file_grid_layout");
        //file_grid_layout.setContentsMargins(1, 1, 1, 1);
        //file_grid_layout.setSpacing(1);
        file_grid_layout.setRowStretch(cols, 1);
        file_grid_layout.setColumnStretch(cols, 1);

        scroll_area.setWidget(file_grid_container);
        center_layout.addWidget(scroll_area);

        // stretch factor
        main_layout.addWidget(center_panel, 1);
    
        auto right_panel = cpp_new!QWidget(central_widget);
        right_panel.setObjectName("right_panel");
        right_panel.setFixedWidth(350);
        right_panel.setStyleSheet(QString(
            "QWidget#right_panel {
                background-color: #ffffff;
                border-left: 1px solid #ccc;
            }"
        ));

        auto right_layout = cpp_new!QVBoxLayout(right_panel);
        right_layout.setContentsMargins(2, 2, 2, 2);

        auto file_info_title = cpp_new!QLabel(right_panel);
        file_info_title.setObjectName("file_info_title");
        file_info_title.setText(QString("File information"));
        auto info_font = cast(qt.gui.font.QFont)file_info_title.font();
        info_font.setBold(true);
        file_info_title.setFont(info_font);
        file_info_title.setStyleSheet(QString(
            "QLabel#file_info_title {
                padding: 5px 4px 6px 4px;
            }"
        ));
        right_layout.addWidget(file_info_title);

        name_panel = cpp_new!QWidget();
        name_panel.hide();
        name_panel.setObjectName("name_panel");
        name_panel.setStyleSheet(QString(
            "QWidget#name_panel { 
                border-top: 1px solid #cccccc;
            }"
        ));
        auto name_layout = cpp_new!QVBoxLayout(name_panel);
        //name_layout.setContentsMargins(2, 2, 2, 2);
        auto name_title = cpp_new!QLabel(name_panel);
        name_title.setObjectName("name_title");
        name_title.setText(QString("Name"));
        name_title.setFont(info_font);
        name_title.setStyleSheet(QString(
            "QLabel#name_title {
                padding: 0;
            }"
        ));
        name_layout.addWidget(name_title);
        name_input = cpp_new!QLineEdit(name_panel);
        name_input.setObjectName("name_input");
        name_input.setCursorPosition(0);
        name_input.setPlaceholderText(QString("Entry name"));
        name_layout.addWidget(name_input);

        auto name_meta_label = cpp_new!QLabel(name_panel);
        name_meta_label.setObjectName("name_meta_label");
        name_meta_label.setText(QString("Metadata"));
        name_meta_label.setFont(info_font);
        name_meta_label.setStyleSheet(QString(
            "QLabel#name_meta_label {
                padding: 0;
            }"
        ));
        name_layout.addWidget(name_meta_label);
        name_meta = cpp_new!QTextEdit(name_panel);
        name_meta.setObjectName("name_meta");
        name_meta.setPlaceholderText(QString("Entry notes"));
        name_layout.addWidget(name_meta);

        right_layout.addWidget(name_panel);

        file_info_label = cpp_new!QLabel(right_panel);
        file_info_label.setObjectName("file_info_label");
        file_info_label.setStyleSheet(QString(
            "QLabel#file_info_label { 
                border-top: 1px solid #cccccc;
            }"
        ));
        file_info_label.setText(QString(""));
        file_info_label.setWordWrap(true);
        file_info_label.setAlignment(
            QFlags!(qt.core.namespace.AlignmentFlag)(
                qt.core.namespace.AlignmentFlag.AlignTop |
                qt.core.namespace.AlignmentFlag.AlignLeft
            )
        );

        right_layout.addWidget(file_info_label, 1);

        btn_tag_file = cpp_new!QPushButton("Tag");
        btn_tag_file.setToolTip(QString("Tag a category to the file"));
        btn_tag_file.setObjectName("btn_tag_file");
        btn_tag_file.setStyleSheet(QString(
            "QPushButton#btn_tag_file {
                background-color: #e8e8e8;
                padding: 4px 16px;
                border: 1px solid #cccccc;
            }
            "
        ));
        btn_tag_file.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        btn_tag_file.hide();
        QObject.connect(btn_tag_file.signal!"clicked", main_window, delegate void() {
            gApp.doTagFile();
        });
        right_layout.addWidget(btn_tag_file);

        btn_open_file = cpp_new!QPushButton("Open");
        btn_open_file.setToolTip(QString("Open the file locally"));
        btn_open_file.hide();
        btn_open_file.setObjectName("btn_open_file");
        btn_open_file.setStyleSheet(QString(
            "QPushButton#btn_open_file {
                background-color: #e8e8e8;
                padding: 4px 16px;
                border: 1px solid #cccccc;
            }
            "
        ));
        btn_open_file.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        QObject.connect(btn_open_file.signal!"clicked", main_window, delegate void() {
            gApp.openFile();
        });
        right_layout.addWidget(btn_open_file);

        btn_save_file = cpp_new!QPushButton("Save");
        btn_save_file.setToolTip(QString("Save the file data"));
        btn_save_file.hide();
        btn_save_file.setObjectName("btn_save_file");
        btn_save_file.setStyleSheet(QString(
            "QPushButton#btn_save_file {
                background-color: #308CC6 !important;
                padding: 4px 16px;
                color: #ffffff;
                border: 1px solid #4285f4;
            }
            "
        ));
        btn_save_file.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));
        QObject.connect(btn_save_file.signal!"clicked", main_window, delegate void() {
            gApp.saveFile();
        });
        right_layout.addWidget(btn_save_file);

        main_layout.addWidget(right_panel);
    }

    private void setupStatusBar()
    {
        auto status_bar = main_window.statusBar();
        auto now = Clock.currTime();
        string date_str = fmtDate(now.day, cast(int)now.month, now.year % 100);
        status_bar_date = cpp_new!QLabel();
        status_bar_date.setText(QString("Version: " ~ app_version ~ " | " ~ date_str));
        status_bar.addWidget(status_bar_date);
    }

    void openFile()
    {
        if (!selected_entry_id) {
            return;
        }

        auto url = QUrl.fromLocalFile(selected_entry.entry_path);
        if (selected_entry.entry_type == "URL") {
            url = QUrl(selected_entry.entry_path);
        }

        QDesktopServices.openUrl(url);
    }

    void saveFile()
    {
        if (!selected_entry_id) {
            return;
        }

        auto status = db.updateEntry(
            selected_entry_id,
            fromQString(name_input.text()),
            fromQString(name_meta.toPlainText())
        );

        if (status) {
            QMessageBox.information(
                main_window,
                QString("Info"),
                QString("Entry has been updated")
            );
            return;
        }

        QMessageBox.warning(
                main_window,
                QString("Error"),
                QString("Failed to update the entry")
            );
    }

    private string fmtDate(int day, int month, int year)
    {
        import std.format : format;
        return format!"Today's date: %02d/%02d/%02d"(day, month, year);
    }

    void refreshCategories()
    {
        clearInfo();
        
        category_list.clear();
        category_list.addItem(QString("All"));

        auto cats = db.getAllCategories();
        foreach (cat; cats) {
            category_list.addItem(QString(cat.name));
        }

        category_list.setCurrentRow(0);
    }

    void refreshFileGrid()
    {
        clearFileGrid();
        clearInfo();

        StoredFile[] files;
        string search_text = fromQString(search_input.text());

        if (search_text.length > 0) {
            btn_clear_search.show();
            if (selected_category_id == -1) {
                files = db.searchEntries(search_text);
            } else {
                files = db.searchEntriesInCategory(search_text, selected_category_id);
            }
        } else {
            if (selected_category_id == -1) {
                files = db.getAllEntries();
            } else {
                files = db.getEntriesByCategory(selected_category_id);
            }
        }

        foreach (i, ref file; files) {
            int row = cast(int)(i / cols);
            int col = cast(int)(i % cols);

            auto btn_file = createFileTile(file);
            file_grid_layout.addWidget(
                btn_file,
                row,
                col,
                QFlags!(qt.core.namespace.AlignmentFlag)(qt.core.namespace.AlignmentFlag.AlignLeft | qt.core.namespace.AlignmentFlag.AlignTop)
            );
        }
    }

    private void clearFileGrid()
    {
        while (file_grid_layout.count() > 0) {
            auto item = file_grid_layout.takeAt(0);
            if (item !is null) {
                auto w = item.widget();
                if (w !is null) {
                    w.setParent(null);
                }
            }
        }
    }

    private QPushButton createFileTile(StoredFile file)
    {
        string ext = file.entry_extension.length > 0 ? file.entry_extension : "";

        // Display: extension badge + filename
        string displayName = file.entry_name.length > 10 ? file.entry_name[0 .. 10] ~ "..." : file.entry_name;
        string icon_file = setIcon(ext);

        auto btn = cpp_new!QPushButton(file_grid_container);
        btn.setFixedSize(QSize(96, 96));
        btn.setCursor(QCursor(qt.core.namespace.CursorShape.PointingHandCursor));

        auto layout = cpp_new!QVBoxLayout(btn);

        auto icon_label = cpp_new!QLabel();
        icon_label.setPixmap(QIcon("./icons/" ~ icon_file ~ ".svg").pixmap(QSize(64, 64)));
        icon_label.setAlignment(QFlags!(qt.core.namespace.AlignmentFlag)(qt.core.namespace.AlignmentFlag.AlignCenter));

        auto text_label = cpp_new!QLabel(QString(displayName));
        text_label.setAlignment(QFlags!(qt.core.namespace.AlignmentFlag)(qt.core.namespace.AlignmentFlag.AlignCenter));

        layout.addWidget(icon_label);
        layout.addWidget(text_label);
        layout.setContentsMargins(5, 5, 5, 5);
        layout.setSpacing(2);

        btn.setLayout(layout);
        btn.setToolTip(QString(file.entry_name));

        // Connect click to show file info
        long fid = file.id;
        QObject.connect(btn.signal!"clicked", main_window, delegate void() {
            gApp.onFileClicked(fid, btn);
        });

        return btn;
    }

    void onFileClicked(long entry_id, QWidget target)
    {
        selected_entry_id = entry_id;        

        if (selection_entry !is null) {
            selection_entry.setProperty("selected", "false");
            selection_entry.style().unpolish(selection_entry);
            selection_entry.style().polish(selection_entry);
        }

        target.setProperty("selected", "true");
        target.style().unpolish(target);
        target.style().polish(target);
        target.update();

        selection_entry = target;

        showFileInfo(selected_entry_id);
    }

    void doAddFile()
    {
        auto entry_name = QFileDialog.getOpenFileName(
            main_window,
            QString("Add File to the File Vault"),
            QString(""),
            QString("All Files (*)")
        );

        string entry_path = fromQString(entry_name);
        if (entry_path.length == 0) {
            return;
        }

        addEntryToDb(entry_path);
        refreshFileGrid();
    }

    void doAddFolder()
    {
        auto dir = QFileDialog.getExistingDirectory(
            main_window,
            QString("Add Folder to the File Vault"),
            QString("")
        );

        string dir_path = fromQString(dir);
        if (dir_path.length == 0) {
            return;
        }

        import std.file : dirEntries, SpanMode;
        try {
            foreach (entry; dirEntries(dir_path, SpanMode.shallow)) {
                if (entry.isFile) {
                    addEntryToDb(
                        entry.name
                    );
                }
            }
        } catch (Exception e) {}

        refreshFileGrid();
    }

    void doAddUrl()
    {
        bool ok;
        auto name = QInputDialog.getText(
            main_window,
            QString("Add URL"),
            QString("URL:"),
            QLineEdit.EchoMode.Normal,
            QString(""),
            &ok
        );

        if (ok) {
            string entry_path = fromQString(name);
            if (entry_path.length > 0) {
                addEntryToDb(entry_path, true);
                refreshFileGrid();
            }
        }
    }

    private void addEntryToDb(string entry_path, bool url = false)
    {
        string entry_name = baseName(entry_path);
        string entry_type = "URL";
        string entry_ext = ".url";
        long entry_size = 0;

        if (!url) {
            entry_ext = extension(entry_path);
            try {
                entry_size = cast(long)getSize(entry_path);
            } catch (Exception e) {}
        }

        long entry_id = db.addEntry(entry_path, entry_name, entry_ext, entry_type, entry_size, "");

        // Auto-tag if a category is selected
        if (selected_category_id > 0 && entry_id > 0) {
            db.tagEntry(entry_id, selected_category_id);
        }
    }

    private string setIcon(string ext)
    {
        return getFileType(ext).toLower();
    }

    private string getFileType(string ext)
    {
        switch (ext)
        {
            case ".pdf":
                return "PDF";
            case ".doc": case ".docx": case ".odt": case ".txt": case ".rtf": 
                return "Document";
            case ".mp3": case ".wav": case ".flac": case ".aac": case ".ogg": 
                return "Audio";
            case ".mp4": case ".avi": case ".mkv": case ".mov": case ".wmv": case ".webm": case ".flv": 
                return "Video";
            case ".jpg": case ".jpeg": case ".png": case ".gif": case ".bmp": case ".svg": 
                return "Image";
            case ".html": case ".htm":
                return "HTML";
            case ".url": 
                return "Website";
            case ".zip": case ".tar": case ".gz": case ".rar": case ".7z": 
                return "Archive";
            default: 
                return "Other";
        }
    }

    void clearInfo()
    {
        file_info_label.setText(QString(""));
        name_input.setText(QString(""));
        name_meta.setText(QString(""));

        name_panel.hide();
        btn_save_file.hide();
        btn_open_file.hide();
        btn_tag_file.hide();
    }

    void doRemoveCategory()
    {
        if (selected_category_id <= 0) {
            QMessageBox.information(
                main_window,
                QString("Info"),
                QString("Please select a category first.")
            );
            return;
        }

        auto reply = QMessageBox.question(
            main_window,
            QString("Confirm"),
            QString("Remove selected category from vault?")
        );

        if (reply == QMessageBox.StandardButton.Yes) {
            db.removeCategory(selected_category_id);
            selected_category_id = -1;
            selected_entry_id = -1;

            refreshCategories();
            //refreshFileGrid();
        }
    }

    void doRemoveFile()
    {
        if (selected_entry_id <= 0) {
            QMessageBox.information(
                main_window,
                QString("Info"),
                QString("Please select an entry first.")
            );
            return;
        }

        auto reply = QMessageBox.question(
            main_window,
            QString("Confirm"),
            QString("Remove selected entry from vault?")
        );

        if (reply == QMessageBox.StandardButton.Yes) {
            db.removeEntry(selected_entry_id);
            selected_entry_id = -1;

            refreshFileGrid();
        }
    }

    void doTagFile()
    {
        if (selected_entry_id <= 0) {
            QMessageBox.information(main_window, QString("Info"),
                QString("Please select a file first."));
            return;
        }

        auto cats = db.getAllCategories();
        if (cats.length == 0) {
            QMessageBox.information(main_window, QString("Info"),
                QString("No categories defined. Add a category first."));
            return;
        }

        auto cat_names = new QStringList();
        foreach (cat; cats) {
            cat_names.append(QString(cat.name));
        }

        bool ok;
        auto selected = QInputDialog.getItem(
            main_window,
            QString("Tag Entry"),
            QString("Please select a category"),
            *cat_names,
            0,
            false,
            &ok
        );

        if (ok) {
            string selected_name = fromQString(selected);
            foreach (cat; cats) {
                if (cat.name == selected_name) {
                    db.tagEntry(selected_entry_id, cat.id);
                    showFileInfo(selected_entry_id);
                    return;
                }
            }
        }
    }

    void doAddCategory()
    {
        bool ok;
        auto name = QInputDialog.getText(
            main_window,
            QString("Add Category"),
            QString("Category name:"),
            QLineEdit.EchoMode.Normal,
            QString(""),
            &ok
        );

        if (ok) {
            string cat_name = fromQString(name);
            if (cat_name.length > 0) {
                db.addCategory(cat_name);
                refreshCategories();
            }
        }
    }

    void doCategoryChanged(int row)
    {
        if (row < 0) {
            return;
        }

        if (row == 0) {
            selected_category_id = -1;
            current_category_label.setText(QString("All"));
        } else {
            auto cats = db.getAllCategories();
            if (row - 1 < cast(int)cats.length) {
                selected_category_id = cats[row - 1].id;
                current_category_label.setText(QString(cats[row - 1].name));
            }
        }

        refreshFileGrid();
    }

    void showFileInfo(long entry_id)
    {
        selected_entry = db.getEntryById(entry_id);

        if (selected_entry.id <= 0) {
            return;
        }

        auto cats = db.getCategoriesForEntry(entry_id);
        string cat_str = "";
    
        foreach (i, cat; cats) {
            if (i > 0) {
                cat_str ~= ", ";
            }
            cat_str ~= cat.name;
        }

        if (cat_str.length == 0) {
            cat_str = "(none)";
        }

        string size_str = formatFileSize(selected_entry.entry_size);

        string info = "Path: " ~ selected_entry.entry_path ~ "\n\n" ~
                      "Type: " ~ selected_entry.entry_type ~ "\n\n" ~
                      "Extension: " ~ selected_entry.entry_extension ~ "\n\n" ~
                      "Size: " ~ size_str ~ "\n\n" ~
                      "Created at: " ~ selected_entry.created_at ~ "\n\n" ~
                      "Updated at: " ~ selected_entry.updated_at ~ "\n\n" ~
                      "Categories: " ~ cat_str;

        file_info_label.setText(QString(info));

        name_input.setText(QString(selected_entry.entry_name));
        name_input.setCursorPosition(0);

        name_meta.setText(QString(selected_entry.metadata));

        name_panel.show();
        btn_save_file.show();
        btn_open_file.show();
        btn_tag_file.show();
    }

    private string formatFileSize(long size)
    {
        if (size < 1024) {
            return to!string(size) ~ " B";
        }

        if (size < 1024 * 1024) {
            return to!string(size / 1024) ~ " KB";
        }

        if (size < 1024 * 1024 * 1024) {
            return to!string(size / (1024 * 1024)) ~ " MB";
        }

        return to!string(size / (1024 * 1024 * 1024)) ~ " GB";
    }

    void show()
    {
        main_window.show();
    }

    int exec(ref QApplication a)
    {
        return a.exec();
    }

    void cleanup()
    {
        db.close();
    }
}

string fromQString(QString qs)
{
    auto ba = qs.toUtf8();
    auto data = ba.constData();

    if (data is null) {
        return "";
    }

    auto len = ba.length();

    if (len <= 0) {
        return "";
    }

    char[] buf = new char[len];
    buf[] = data[0 .. len];

    return cast(string)buf;
}

int main()
{
    scope a = new QApplication(Runtime.cArgs.argc, Runtime.cArgs.argv);

    auto app = new FileVaultApp();
    gApp = app;
    app.initialize();
    app.show();

    int result = app.exec(a);
    app.cleanup();
    return result;
}
