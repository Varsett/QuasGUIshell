# Quas GUI Shell v5.12
### (English manual below)


**Графическая оболочка для ADB и управления Meta Quest VR**

Автор: Varset & Gemini Dev | Рефакторинг 2026

---

## Обзор

Quas GUI Shell — это WinForms-оболочка на PowerShell 5.1 для работы с ADB (Android Debug Bridge) и общими командами оболочки, созданная специально для управления VR-шлемами Meta Quest. Интерфейс включает многовкладочный редактор, цветной лог вывода, сворачиваемую панель хинтов с библиотекой команд, умный перехватчик интерактивных команд, а также тёмную и светлую тему оформления.

Скрипт является частью сборки **Quas** — комплексного инструментария для управления Meta Quest под Windows — и обычно запускается из главного EXE-файла Quas.

![](https://github.com/Varsett/pictures/blob/8211c004986e1895f7745ded55029b6352164702/GUIShell_v5.12.jpg)



---

## Требования

- Windows 10 / 11
- PowerShell 5.1 (встроен в Windows, установка не требуется)
- ADB (Android Debug Bridge) — входит в сборку Quas, либо из Android SDK Platform Tools
- Шлем Meta Quest с включённой отладкой по USB (Настройки > Разработчик)

---

## Запуск

### Самостоятельно (PowerShell или CMD)

```powershell
powershell -File QuasGUIShell.ps1
powershell -File QuasGUIShell.ps1 -ToolsPath "C:\ADB"
```

### Из CMD-скрипта

```bat
powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%SCRIPT_PATH%\QuasGUIShell.ps1" ^
  -ToolsPath "%TOOLS_PATH%"
```

### Из сборки Quas EXE

Запускается автоматически из главного меню Quas. Скрипт распаковывается в `%TEMP%` — настройки и hints.txt читаются из папки рядом с EXE.

---

## Параметры

| Параметр     | Тип    | По умолч. | Описание                                                          |
|--------------|--------|-----------|-------------------------------------------------------------------|
| `-ToolsPath` | String | (пусто)   | Путь к папке с `adb.exe`, `fastboot.exe` и др. Добавляется в `PATH` на время сессии. |

---

## Структура интерфейса

```
+----------------------------------------------------------+--хинты----+
|  Вкладка 1   Вкладка 2   [+]                            | Фильтр... |
+----------------------------------------------------------+ [+][-][R] |
|                                                          | >Инфо     |
|   РЕДАКТОР  (буфер команд активной вкладки)              |   adb dev |
|                                                          |   adb she |
|                                                          | >Приложения|
+----------------------------------------------------------+-----------+
|   ЛОГ  (вывод выполненных команд, только активная вкладка)          |
+----------------------------------------------------------------------+
| [Run] [STOP] [Paste] [Clear] [U] [Copy] [Save] [Detach] [Clear] [U]|
| Log Search: [___________] [Highlight] [Timestamps] [Extract]        |
| Tab: Вкладка 1 | Lines: 5                                           |
+----------------------------------------------------------------------+
```

---

## Вкладки

Каждая вкладка имеет **независимый редактор и лог**. Переключение вкладок мгновенно меняет оба окна.

| Действие                   | Результат                          |
|----------------------------|------------------------------------|
| Кнопка `[+]`               | Создать новую вкладку              |
| `Ctrl+T`                   | Создать новую вкладку              |
| Клик по имени вкладки      | Переключиться на неё               |
| Двойной клик по имени      | Переименовать вкладку              |
| `[x]` на вкладке           | Закрыть (минимум одна остаётся)    |
| `Ctrl+W`                   | Закрыть активную вкладку           |
| `Ctrl+Tab`                 | Перейти к следующей вкладке        |

---

## Редактор

Введите команды — по одной на строку. При нажатии **F5** или **[Run]** они выполняются последовательно сверху вниз.

- **Пустые строки** пропускаются автоматически
- **Комментарии** (`# текст`) НЕ пропускаются — они передаются в CMD как есть
- Каждая команда имеет **таймаут 20 секунд** — при превышении процесс убивается и в логе появляется `[TIMEOUT]`

### Пример — блок информации об устройстве

```
adb devices -l
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell uptime
adb shell dumpsys battery
```

### Управление редактором

| Кнопка / Клавиша  | Действие                                      |
|-------------------|-----------------------------------------------|
| `F5` / `[Run]`    | Выполнить все строки сверху вниз              |
| `[STOP]`          | Прервать очередь после текущей команды        |
| `[Paste]`         | Вставить текст из буфера обмена в редактор    |
| `[Clear Code]`    | Очистить редактор (сохраняется для Undo)      |
| `[U]` (левый)     | Восстановить последнее очищенное содержимое   |
| `Ctrl+A`          | Выделить всё в редакторе                      |

---

## Умный перехватчик (Smart Interceptor)

Некоторые команды интерактивны (открывают приглашение оболочки) или выдают бесконечный поток вывода (например, `logcat`). Их выполнение в GUI-логе заморозило бы интерфейс.

Перехватчик **автоматически определяет** такие команды и открывает их во внешней консоли. В логе при этом появляется сообщение `[REDIRECT]`.

### Перехватываются автоматически

| Категория  | Команды                                                                 |
|------------|-------------------------------------------------------------------------|
| Оболочки   | `cmd`, `powershell`, `pwsh`, `adb shell` (без аргументов), `ftp`, `ssh`, `nslookup`, `python`, `node` |
| Потоки     | `adb shell top`, `ping -t`, `adb logcat` (без флага `-d`), `watch`, `monitor` |
| Тяжёлые    | `scrcpy`, `diskpart`, `telnet`                                          |

### Режим внешнего окна

- `cmd /k` — окно остаётся открытым после завершения (большинство команд)
- `cmd /c` — закрывается после завершения (adb, scrcpy)
- `powershell -NoExit` — для команд powershell/pwsh

---

## Панель лога

| Кнопка           | Действие                                                         |
|------------------|------------------------------------------------------------------|
| `[Copy Log]`     | Скопировать весь активный лог в буфер обмена                     |
| `[Save Log]`     | Экспортировать лог в файл `.txt` в кодировке UTF-8               |
| `[Detach Log]`   | Открыть лог в отдельном окне с собственным поиском               |
| `[Clear Log]`    | Очистить лог (сохраняется для Undo)                              |
| `[U]` (правый)   | Восстановить последнее очищенное содержимое лога                 |
| `[Timestamps]`   | Включить/выключить заголовок `--- Run at HH:mm:ss ---`           |

### Цветовая кодировка лога

| Цвет    | Значение                                           |
|---------|----------------------------------------------------|
| Голубой | Строка эха `> команда`                             |
| Белый   | Обычный вывод stdout                               |
| Красный | Вывод stderr (ошибки)                              |
| Оранжевый | Сообщения `[REDIRECT]` и `[TIMEOUT]`             |
| Серый   | Временные метки и подсказки                        |

---

## Поиск по логу

Всегда виден в нижней панели — скрывать не нужно.

- Введите **3+ символа** для подсветки всех совпадений жёлтым
- `[Highlight]` — включить/выключить подсветку "Soft Vision"
- `[Extract to Notepad]` — извлечь все строки с совпадением во временный `.txt` файл в Блокноте

### Пример рабочего процесса

1. Запустите пакет adb-команд
2. Введите `error` в поле поиска
3. Все совпадающие строки подсветятся жёлтым
4. Нажмите **Extract to Notepad** для чистого отфильтрованного отчёта

---

## Панель хинтов

Правая боковая панель отображает команды из `hints.txt`, сгруппированные в сворачиваемые категории.

| Действие                     | Результат                                            |
|------------------------------|------------------------------------------------------|
| Двойной клик по команде      | Вставить в активный редактор                         |
| Клик по заголовку категории  | Развернуть / свернуть категорию                      |
| `[+ Expand]`                 | Развернуть все категории                             |
| `[- Collapse]`               | Свернуть все категории                               |
| `[Reload]`                   | Перечитать `hints.txt` без перезапуска               |
| Поле фильтра                 | Живой поиск по всем категориям                       |
| `[Hints On/Off]`             | Показать / скрыть всю боковую панель                 |

### Цветовая маркировка команд в хинтах

| Префикс | Цвет    | Значение                                                    |
|---------|---------|-------------------------------------------------------------|
| `!`     | Красный | **ОПАСНО** — необратимо (удаление файлов, сброс, принудительная перезагрузка) |
| `~`     | Жёлтый  | **ОСТОРОЖНО** — меняет настройки или состояние устройства   |
| нет     | Обычный | Безопасно — только чтение или информация                    |

Префикс убирается перед отображением и перед вставкой в редактор. При наведении курсора на команду отображается подсказка `[DANGER]` или `[CAUTION]`.

---

## Формат hints.txt

Разместите `hints.txt` в той же папке, что и скрипт, или в подпапке `Source`.

```
[ Информация о системе ]
adb devices
adb devices -l
adb shell getprop ro.product.model

[ Приложения ]
adb shell pm list packages -3
~adb shell pm disable-user --user 0 <pkgname>
!adb shell pm uninstall <pkgname>

[ Quest VR ]
~adb shell setprop debug.oculus.cpuLevel 4
~adb shell setprop debug.oculus.gpuLevel 4

# Это комментарий - строка пропускается
# --- Устаревший стиль ---   (тоже поддерживается)
# === Ещё один вариант ===   (тоже поддерживается)
```

---

## Горячие клавиши

| Клавиши      | Действие                           |
|--------------|------------------------------------|
| `F5`         | Выполнить все команды в редакторе  |
| `Ctrl+A`     | Выделить всё в редакторе           |
| `Ctrl+T`     | Новая вкладка                      |
| `Ctrl+W`     | Закрыть активную вкладку           |
| `Ctrl+Tab`   | Переключиться на следующую вкладку |

---

## Тема и компоновка

- **[Theme]** — переключить тёмную / светлую тему
- **[Hints On/Off]** — показать или скрыть правую боковую панель
- **Горизонтальный разделитель** — перетащите для изменения соотношения высоты редактора и лога
- **Вертикальный разделитель** — перетащите для изменения ширины редактора и панели хинтов

---

## Устранение неполадок

| Проблема                         | Решение                                                                    |
|----------------------------------|----------------------------------------------------------------------------|
| `adb` не найден                  | Укажите `-ToolsPath` с путём к папке с `adb.exe`                           |
| Команда зависает интерфейс       | Должна была перехватиться — проверьте правила перехватчика                 |
| `[TIMEOUT]` через 20 секунд      | Команда интерактивная — перехватчик должен открыть внешнюю консоль         |
| Хинты не обновляются             | Нажмите `[Reload]` после редактирования `hints.txt`                        |
| Кириллица в выводе — кракозябры  | Известное ограничение: несовместимость UTF-8 (CMD) и CP1251 (PS 5.1). Вывод ADB — ASCII, проблем нет. |

---

## Структура файлов

```
QuasGUIShell.ps1      Основной скрипт
hints.txt             Библиотека команд (или Source\hints.txt)
```

---

## Лицензия

Часть сборки **Quas**. Подробности лицензии — в репозитории.


> https://github.com/Varsett/QuasGUIshell

---

---
# Quas GUI Shell v5.12

**Advanced ADB and Command Interface Manager for Meta Quest VR headsets**

Created by Varset & Gemini Dev | Refactored 2026

---

## Overview

Quas GUI Shell is a PowerShell 5.1 WinForms GUI wrapper for ADB (Android Debug Bridge) and general shell commands, built specifically for managing Meta Quest VR headsets. It provides a multi-tab editor, colorized output log, collapsible hints panel with command library, smart interceptor for interactive commands, and a dark/light theme.

It is part of the **Quas** toolkit — a comprehensive Windows toolset for Meta Quest management — and is typically launched from the main Quas EXE bundle.

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 (built into Windows, no install needed)
- ADB (Android Debug Bridge) — included in the Quas bundle, or separately from Android SDK Platform Tools
- Meta Quest headset with USB Debugging enabled (Settings > Developer)

---

## Launch

### Standalone (PowerShell or CMD)

```powershell
powershell -File QuasGUIShell.ps1
powershell -File QuasGUIShell.ps1 -ToolsPath "C:\ADB"
```

### From CMD batch script

```bat
powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%SCRIPT_PATH%\QuasGUIShell.ps1" ^
  -ToolsPath "%TOOLS_PATH%"
```

### From Quas EXE bundle

Launched automatically by the main Quas menu. The script unpacks to `%TEMP%` — settings and hints.txt are read from the folder next to the EXE.

---

## Parameters

| Parameter    | Type   | Default | Description                                              |
|--------------|--------|---------|----------------------------------------------------------|
| `-ToolsPath` | String | (empty) | Path to folder containing `adb.exe`, `fastboot.exe`, etc. Prepended to `PATH` for the session. |

---

## Interface Overview

```
+----------------------------------------------------------+---hints---+
|  Tab 1    Tab 2    Tab 3   [+]                           | Filter... |
+----------------------------------------------------------+ [+][-][R] |
|                                                          | >Info     |
|   EDITOR  (active tab command buffer)                    |   adb dev |
|                                                          |   adb she |
|                                                          | >Apps     |
|                                                          |   adb pm  |
+----------------------------------------------------------+-----------+
|   LOG  (output of executed commands, active tab only)               |
+----------------------------------------------------------------------+
| [Run] [STOP] [Paste] [Clear] [U] [Copy] [Save] [Detach] [Clear] [U]|
| Log Search: [___________] [Highlight] [Timestamps] [Extract]        |
| Tab: Tab 1 | Lines: 5                                               |
+----------------------------------------------------------------------+
```

---

## Tabs

Each tab has its own **independent editor and log**. Switching tabs instantly swaps both panels.

| Action                  | Result                        |
|-------------------------|-------------------------------|
| `[+]` button            | Create new tab                |
| `Ctrl+T`                | Create new tab                |
| Click tab name          | Switch to that tab            |
| Double-click tab name   | Rename the tab                |
| `[x]` on tab            | Close tab (min 1 always kept) |
| `Ctrl+W`                | Close active tab              |
| `Ctrl+Tab`              | Cycle to next tab             |

---

## Editor

Write commands one per line. Lines are executed sequentially when you press **F5** or **[Run]**.

- **Blank lines** are skipped automatically
- **Comments** (`# text`) are NOT skipped — they are sent to CMD as-is
- Each command has a **20-second timeout** — if exceeded, the process is killed and `[TIMEOUT]` appears in the log

### Example — device info block

```
adb devices -l
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell uptime
adb shell dumpsys battery
```

### Editor controls

| Button / Key      | Action                                   |
|-------------------|------------------------------------------|
| `F5` / `[Run]`    | Execute all lines top to bottom          |
| `[STOP]`          | Abort queue after current command        |
| `[Paste]`         | Append clipboard to editor               |
| `[Clear Code]`    | Clear editor (saved for Undo)            |
| `[U]` (left)      | Restore last cleared editor content      |
| `Ctrl+A`          | Select all in editor                     |

---

## Smart Interceptor

Some commands are interactive (open a shell prompt) or produce infinite output (like `logcat`). Running them in the GUI log would freeze the interface.

The interceptor **automatically detects** these and opens them in an external console instead. A `[REDIRECT]` message appears in the log.

### Intercepted automatically

| Category | Commands                                                      |
|----------|---------------------------------------------------------------|
| Shells   | `cmd`, `powershell`, `pwsh`, `adb shell` (bare), `ftp`, `ssh`, `nslookup`, `python`, `node` |
| Streams  | `adb shell top`, `ping -t`, `adb logcat` (without `-d`), `watch`, `monitor` |
| Heavy    | `scrcpy`, `diskpart`, `telnet`                                |

### External window behavior

- `cmd /k` — stays open after command finishes (most commands)
- `cmd /c` — closes after finish (adb, scrcpy)
- `powershell -NoExit` — for powershell/pwsh commands

---

## Log Panel

| Button          | Action                                                         |
|-----------------|----------------------------------------------------------------|
| `[Copy Log]`    | Copy entire active log to clipboard                            |
| `[Save Log]`    | Export active log to UTF-8 `.txt` file                         |
| `[Detach Log]`  | Open log in a separate resizable window with its own search    |
| `[Clear Log]`   | Clear log (saved for Undo)                                     |
| `[U]` (right)   | Restore last cleared log content                               |
| `[Timestamps]`  | Toggle `--- Run at HH:mm:ss ---` header before each run block  |

### Log color coding

| Color  | Meaning                                      |
|--------|----------------------------------------------|
| Cyan   | `> command` echo line                        |
| White  | Normal stdout output                         |
| Red    | Stderr output (errors)                       |
| Orange | `[REDIRECT]` and `[TIMEOUT]` notices         |
| Grey   | Timestamp headers and advice messages        |

---

## Log Search

Always visible in the bottom panel — no toggle needed.

- Type **3+ characters** to highlight all matches in yellow
- `[Highlight]` — enable/disable yellow soft-vision highlight
- `[Extract to Notepad]` — pull all matching lines into a temp `.txt` file opened in Notepad

### Example workflow

1. Run a batch of adb commands
2. Type `error` in the search box
3. All matching lines glow yellow
4. Click **Extract to Notepad** for a clean filtered report

---

## Hints Panel

The right sidebar shows commands from `hints.txt` grouped into collapsible categories.

| Action                   | Result                                          |
|--------------------------|-------------------------------------------------|
| Double-click command     | Insert into active editor                       |
| Click category header    | Expand / collapse that category                 |
| `[+ Expand]`             | Expand all categories                           |
| `[- Collapse]`           | Collapse all categories                         |
| `[Reload]`               | Re-read `hints.txt` without restarting          |
| Filter box               | Live search across all categories               |
| `[Hints On/Off]`         | Show / hide the entire sidebar                  |

### Command color coding

| Prefix | Color  | Meaning                                              |
|--------|--------|------------------------------------------------------|
| `!`    | Red    | **DANGER** — irreversible (delete files, wipe data, force-reboot) |
| `~`    | Yellow | **CAUTION** — changes settings or device state       |
| none   | Normal | Safe — read-only or informational                    |

The prefix is stripped before display and before insertion into the editor. Hover over a command to see `[DANGER]` or `[CAUTION]` in the tooltip.

---

## hints.txt Format

Place `hints.txt` in the same folder as the script, or in a `Source` subfolder.

```
[ Info & Status ]
adb devices
adb devices -l
adb shell getprop ro.product.model

[ Apps ]
adb shell pm list packages -3
~adb shell pm disable-user --user 0 <pkgname>
!adb shell pm uninstall <pkgname>

[ Quest VR ]
~adb shell setprop debug.oculus.cpuLevel 4
~adb shell setprop debug.oculus.gpuLevel 4

# This is a comment - skipped
# --- Legacy Section ---   (also supported)
# === Legacy Style ===      (also supported)
```

---

## Keyboard Shortcuts

| Shortcut     | Action                        |
|--------------|-------------------------------|
| `F5`         | Run all commands in editor    |
| `Ctrl+A`     | Select all in editor          |
| `Ctrl+T`     | New tab                       |
| `Ctrl+W`     | Close active tab              |
| `Ctrl+Tab`   | Switch to next tab            |

---

## Theme and Layout

- **[Theme]** — toggle Dark / Light visual mode
- **[Hints On/Off]** — show or hide the right sidebar
- **Horizontal splitter** — drag to resize editor vs log height
- **Vertical splitter** — drag to resize editor vs hints panel width

---

## Troubleshooting

| Problem                        | Solution                                                                 |
|--------------------------------|--------------------------------------------------------------------------|
| `adb` not found                | Pass `-ToolsPath` pointing to the folder with `adb.exe`                  |
| Command freezes the GUI        | It should have been intercepted — check if it matches interceptor rules  |
| `[TIMEOUT]` after 20 seconds   | Command is interactive — let the interceptor redirect it to external CMD |
| Hints not updating             | Click `[Reload]` after editing `hints.txt`                               |
| Cyrillic output appears garbled | Known limitation: CMD UTF-8 vs PS 5.1 CP1251 encoding mismatch. ADB output is ASCII and unaffected. |

---

## File Structure

```
QuasGUIShell.ps1      Main script
hints.txt             Command library (or Source\hints.txt)
```

---

## License

Part of the **Quas** toolkit. See repository for license details.

> https://github.com/Varsett/QuasGUIshell
