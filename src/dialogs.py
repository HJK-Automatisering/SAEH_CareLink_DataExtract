import ctypes
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, ttk

# Sharp text on high-DPI screens instead of blurry, scaled-up windows
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(1)
except (AttributeError, OSError):
    pass

def show_console():
    """Bring the console window back up, so the result can be read (the .bat starts it minimized)."""
    try:
        hwnd = ctypes.windll.kernel32.GetConsoleWindow()
        if hwnd:
            ctypes.windll.user32.ShowWindow(hwnd, 9)  # SW_RESTORE
            ctypes.windll.user32.SetForegroundWindow(hwnd)
    except (AttributeError, OSError):
        pass

def choose_xls_file():
    """Show a file picker and return the chosen .xls path, or None if the user cancels."""
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)  # keep the picker in front of the console window

    downloads = Path.home() / "Downloads"
    path = filedialog.askopenfilename(
        parent=root,
        title="Vælg Dækningsrapport .xls-filen",
        initialdir=downloads if downloads.is_dir() else Path.home(),
        filetypes=[("Excel 97-2003 (*.xls)", "*.xls")],
    )
    root.destroy()
    return path or None

def popup(title, message, buttons, default, warning=None, on_close=None):
    """Show a popup and return the text of the button clicked.

    A warning is shown in red above the message. Closing the window or pressing Esc returns on_close
    (the last button if not given).
    """
    on_close = on_close or buttons[-1]
    root = tk.Tk()
    root.title(title)
    root.resizable(False, False)
    root.attributes("-topmost", True)

    answer = {"button": on_close}
    def choose(text):
        answer["button"] = text
        root.destroy()

    frame = ttk.Frame(root, padding=20)
    frame.pack()

    if warning:
        tk.Label(frame, text=warning, fg="#b00020", font=("Segoe UI", 10, "bold"),
                 justify="left", wraplength=480).pack(anchor="w", pady=(0, 12))
    tk.Label(frame, text=message, font=("Segoe UI", 10), justify="left").pack(anchor="w")

    row = ttk.Frame(frame)
    row.pack(anchor="e", pady=(20, 0))
    default_button = None
    for i, text in enumerate(buttons):
        button = ttk.Button(row, text=text, width=10, command=lambda t=text: choose(t))
        button.pack(side="left", padx=(8 if i else 0, 0))
        if text == default:
            default_button = button

    def press_enter(event):
        focused = root.focus_get()
        (focused if isinstance(focused, ttk.Button) else default_button).invoke()
    root.bind("<Return>", press_enter)
    root.bind("<Escape>", lambda e: choose(on_close))
    root.protocol("WM_DELETE_WINDOW", lambda: choose(on_close))

    # Centre on screen and bring in front of the console window
    root.update_idletasks()
    root.eval("tk::PlaceWindow . center")
    root.lift()
    root.focus_force()
    default_button.focus_set()  # after focus_force, otherwise the window takes the focus and Enter does nothing

    root.mainloop()
    return answer["button"]

def ask_ja_nej(title, message, warning=None):
    """Ja/Nej popup; True for Ja. With a warning, Nej is the default button. Closing or Esc counts as Nej."""
    return popup(title, message, ["Ja", "Nej"], default="Nej" if warning else "Ja", warning=warning) == "Ja"

def ask_behold_slet(title, message, warning=None):
    """Behold/Slet popup; True for Slet. Behold is the default, and closing or Esc also counts as Behold."""
    return popup(title, message, ["Behold", "Slet"], default="Behold", warning=warning, on_close="Behold") == "Slet"

def show_info(title, message):
    """Popup with only an OK button."""
    popup(title, message, ["OK"], default="OK")
