"""iPhone BLE Camera Remote — Windows laptop GUI. Local commands only.

Requires a matching iOS companion app in the foreground and Bluetooth LE.
Video stays on the iPhone; it is never transmitted over Bluetooth.
"""
from __future__ import annotations

import asyncio
import queue
import threading
import tkinter as tk
import time
import io
import ipaddress
import re
import urllib.request
import urllib.error
from urllib.parse import urlsplit, parse_qs, urlencode
from PIL import Image, ImageTk
from dataclasses import dataclass
from datetime import datetime
from tkinter import messagebox, ttk

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    raise SystemExit("Missing dependency. Run START_WINDOWS.bat to install bleak.")

SERVICE_UUID = "e919bc34-11b2-4bea-b102-dc37195206ad"
COMMAND_UUID = "e919bc34-11b2-4bea-b102-dc37195206ae"
STATUS_UUID = "e919bc34-11b2-4bea-b102-dc37195206af"

COLORS = {
    "background": "#080d15", "panel": "#111b2a", "border": "#2a394d",
    "foreground": "#f5f7fa", "muted": "#a3b3c7", "accent": "#6fecc5",
    "blue": "#6fecc5", "warning": "#f1c66d", "red": "#f06680",
}


@dataclass
class Device:
    name: str
    address: str


class BluetoothWorker:
    def __init__(self, event_queue: queue.Queue):
        self.events = event_queue
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self._run, name="ble-worker", daemon=True)
        self._notification_buffer = bytearray()
        self.thread.start()
        self.client: BleakClient | None = None
        self.authorized = False
        self.connected = False
        self.available_devices: list[Device] = []

    def _run(self):
        asyncio.set_event_loop(self.loop)
        try:
            self.loop.run_forever()
        finally:
            pending = asyncio.all_tasks(self.loop)
            for task in pending: task.cancel()
            if pending:
                self.loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            self.loop.close()

    def submit(self, coroutine):
        future = asyncio.run_coroutine_threadsafe(coroutine, self.loop)
        future.add_done_callback(self._report_exception)

    def _report_exception(self, future):
        try:
            future.result()
        except asyncio.CancelledError:
            return
        except Exception as exc:
            self.events.put(("error", str(exc)))

    async def scan(self):
        self.events.put(("log", "Scanning for iPhone camera BLE service (8 seconds)..."))
        try:
            records = await BleakScanner.discover(timeout=8.0, return_adv=True)
            devices: list[Device] = []
            seen: set[str] = set()
            for device, advertisement in records.values():
                uuids = {item.lower() for item in (advertisement.service_uuids or [])}
                if SERVICE_UUID.lower() not in uuids:
                    continue
                if device.address in seen:
                    continue
                seen.add(device.address)
                name = advertisement.local_name or device.name or "iPhone BLE Camera"
                devices.append(Device(name=name, address=device.address))
            self.available_devices = devices
            self.events.put(("devices", devices))
            self.events.put(("log", f"Scan complete: {len(devices)} camera device(s) found."))
        except Exception as exc:
            self.events.put(("error", f"Scan failed: {exc}"))

    async def connect(self, address: str, pin: str):
        if not pin.isascii() or not pin.isdigit() or len(pin) != 6:
            self.events.put(("error", "Enter the six-digit code shown by the iPhone app."))
            return
        if self.client:
            await self.disconnect()
        self.events.put(("log", "Connecting..."))
        try:
            client = BleakClient(address, disconnected_callback=self._disconnected, timeout=20.0)
            self.client = client
            self._notification_buffer.clear()
            await client.connect()
            self.client = client
            self.connected = True
            self.authorized = False
            await client.start_notify(STATUS_UUID, self._notification)
            self.events.put(("connected", True))
            self.events.put(("log", "Connected. Checking PIN..."))
            await client.write_gatt_char(COMMAND_UUID, f"AUTH:{pin}".encode("utf-8"), response=True)
        except Exception as exc:
            self.events.put(("error", f"Connection failed: {exc}"))
            await self.disconnect()

    def _disconnected(self, _client):
        if self.client is not _client:
            return
        self.connected = False
        self.authorized = False
        self.client = None
        self.events.put(("connected", False))
        self.events.put(("log", "iPhone disconnected."))

    def _notification(self, _characteristic, value: bytearray):
        self._notification_buffer.extend(value)
        if len(self._notification_buffer) > 4096:
            self._notification_buffer.clear()
            self.events.put(("error", "Invalid oversized status from iPhone"))
            return
        while b"\n" in self._notification_buffer:
            packet, _, remaining = self._notification_buffer.partition(b"\n")
            self._notification_buffer[:] = remaining
            self._handle_message(packet.decode("utf-8", errors="replace"))

    def _handle_message(self, message):
        self.events.put(("message", message))
        if message == "OK:AUTH":
            self.authorized = True
            self.events.put(("authorized", True))
        elif message.startswith("ERR:AUTH"):
            self.authorized = False
            self.events.put(("authorized", False))

    async def command(self, command: str):
        if not self.client or not self.client.is_connected:
            self.events.put(("error", "Not connected. Scan and connect first."))
            return
        if not self.authorized:
            self.events.put(("error", "PIN has not been accepted by the iPhone."))
            return
        try:
            await self.client.write_gatt_char(COMMAND_UUID, command.encode("utf-8"), response=True)
            self.events.put(("log", f"Sent: {command}"))
        except Exception as exc:
            self.events.put(("error", f"Command error: {exc}"))

    async def disconnect(self):
        client = self.client
        self.client = None
        self.authorized = False
        self.connected = False
        if client:
            try:
                if client.is_connected:
                    await client.disconnect()
            except Exception:
                pass
        self.events.put(("connected", False))
        self.events.put(("authorized", False))



def preview_frame_url(address: str) -> str:
    """Only accept the local, token-protected link shown by the iPhone."""
    url = urlsplit(address.strip())
    try:
        host = ipaddress.IPv4Address(url.hostname or "")
        port = url.port
    except ValueError as exc:
        raise ValueError("Paste the numeric local Wi-Fi link shown on iPhone") from exc
    allowed = any(host in net for net in (ipaddress.ip_network("10.0.0.0/8"),
        ipaddress.ip_network("172.16.0.0/12"), ipaddress.ip_network("192.168.0.0/16"),
        ipaddress.ip_network("127.0.0.0/8")))
    key = parse_qs(url.query).get("key", [""])[0]
    if (url.scheme != "http" or not allowed or port is None or url.username or url.password
            or url.path not in ("", "/", "/frame") or not re.fullmatch(r"[a-fA-F0-9]{32}", key)):
        raise ValueError("Use the full local Wi-Fi link from the iPhone, including its key")
    return f"http://{host}:{port}/frame?{urlencode({'key': key})}"


class NoPreviewRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Preview redirects are not allowed; use the iPhone link")


class PreviewWorker:
    def __init__(self, address):
        self.url = preview_frame_url(address)
        self.frames = queue.Queue(maxsize=2)
        self.stopped = threading.Event()
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoPreviewRedirect())
        self.thread = threading.Thread(target=self._run, daemon=True, name="wifi-preview")

    def _put(self, kind, value):
        try:
            self.frames.put_nowait((kind, value))
        except queue.Full:
            try: self.frames.get_nowait()
            except queue.Empty: pass
            try: self.frames.put_nowait((kind, value))
            except queue.Full: pass

    def _run(self):
        last_status = 0.0
        while not self.stopped.is_set():
            try:
                request = urllib.request.Request(self.url, headers={"Cache-Control": "no-cache"})
                with self.opener.open(request, timeout=2) as response:
                    if response.headers.get_content_type() != "image/jpeg":
                        raise ValueError("iPhone did not return a preview image")
                    data = response.read(512 * 1024 + 1)
                    if len(data) > 512 * 1024 or not data.startswith(b"\xff\xd8"):
                        raise ValueError("Invalid preview image")
                self._put("frame", data)
                if time.monotonic() - last_status >= 1:
                    last_status = time.monotonic()
                    command_url = self.url.replace("/frame?", "/command?", 1)
                    status_request = urllib.request.Request(command_url, data=b"STATUS",
                        headers={"Content-Type": "text/plain"}, method="POST")
                    with self.opener.open(status_request, timeout=2) as status_response:
                        status = status_response.read(4096).decode("utf-8")
                    if status.startswith("STATUS:"): self._put("camera_status", status)
            except urllib.error.HTTPError as exc:
                self._put("status", "Waiting for camera frames…" if exc.code == 503 else "Preview access denied. Copy a fresh link from iPhone.")
            except Exception:
                self._put("status", "Preview disconnected. Check same Wi-Fi, iPhone app and Local Network permission.")
            self.stopped.wait(0.2)

    def stop(self): self.stopped.set()

class CameraRemoteApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Camera Studio — iPhone Remote")
        self.geometry("1280x800")
        self.minsize(980, 650)
        self.state("zoomed")
        self.configure(bg=COLORS["background"])
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("TNotebook", background=COLORS["background"], borderwidth=0)
        style.configure("TNotebook.Tab", background=COLORS["panel"], foreground=COLORS["muted"],
                        padding=(20, 12), font=("Segoe UI", 11, "bold"), borderwidth=0)
        style.map("TNotebook.Tab", background=[("selected", COLORS["accent"])],
                  foreground=[("selected", COLORS["background"])])
        style.configure("TCombobox", fieldbackground="#0b1420", background=COLORS["border"],
                        foreground=COLORS["foreground"], arrowcolor=COLORS["accent"], padding=7,
                        font=("Segoe UI", 11), bordercolor=COLORS["border"])
        style.map("TCombobox", fieldbackground=[("readonly", "#0b1420")],
                  foreground=[("readonly", COLORS["foreground"])],
                  selectbackground=[("readonly", "#0b1420")], selectforeground=[("readonly", COLORS["foreground"])])
        self.option_add("*TCombobox*Listbox.background", COLORS["panel"])
        self.option_add("*TCombobox*Listbox.foreground", COLORS["foreground"])
        self.option_add("*TCombobox*Listbox.selectBackground", COLORS["border"])
        self.events: queue.Queue = queue.Queue()
        self.worker = BluetoothWorker(self.events)
        self.devices: list[Device] = []
        self.connection_ok = False
        self.authorized = False
        self.mode_var = tk.StringVar(value="1080P30")
        self.camera_var = tk.StringVar(value="BACK")
        self.pin_var = tk.StringVar(value="")
        self.device_var = tk.StringVar(value="")
        self.state_var = tk.StringVar(value="DISCONNECTED")
        self.recording_var = tk.StringVar(value="Not recording")
        self.info_var = tk.StringVar(value="Bluetooth = control only • Videos are saved on iPhone")
        self.recording_active = False
        self.busy_recording = False
        self.mode_dirty = False
        self.live_buttons = []
        self.confirmed_quality = tk.StringVar(value="Confirmed recording quality: waiting for iPhone")
        self.clip_quality = tk.StringVar(value="Saved clip metadata: not checked yet")
        self.recording_since = None
        self.timer_var = tk.StringVar(value="00:00:00")
        self.save_var = tk.StringVar(value="Recordings stay on iPhone • Files backup + Photos with permission")
        self.preview_worker = None
        self.preview_photo = None
        self.preview_last_frame = 0
        self.preview_address = tk.StringVar()
        self.preview_status = tk.StringVar(value="Enable Wi-Fi preview on iPhone, then paste its link here")
        self._build_ui()
        self.after(100, self._poll_preview)
        self.after(250, self._tick)
        self.after(100, self._pump)
        self.protocol("WM_DELETE_WINDOW", self._close)

    def _label(self, parent, value, size=11, color=None, bold=False):
        return tk.Label(parent, text=value, bg=parent.cget("bg"),
                        fg=color or COLORS["foreground"],
                        font=("Segoe UI", size, "bold" if bold else "normal"))

    def _frame(self, parent, pad=15):
        frame = tk.Frame(parent, bg=COLORS["panel"], padx=pad, pady=pad,
                         highlightthickness=1, highlightbackground=COLORS["border"])
        frame.pack(fill="x", padx=22, pady=(0, 14))
        return frame

    def _button(self, parent, text, action, primary=False, width=None):
        button = tk.Button(parent, text=text, command=action,
                           bg=COLORS["blue"] if primary else "#31445f",
                           fg=COLORS["background"] if primary else COLORS["foreground"], activebackground="#3b806f" if primary else COLORS["border"],
                           activeforeground="white", bd=0, padx=16, pady=9,
                           cursor="hand2", font=("Segoe UI", 10, "bold"), width=width)
        return button

    def _build_ui(self):
        self.columnconfigure(0, weight=2, uniform="studio")
        self.columnconfigure(1, weight=1, uniform="studio")
        self.rowconfigure(1, weight=1)
        header = tk.Frame(self, bg=COLORS["background"], padx=28, pady=20)
        header.grid(row=0, column=0, columnspan=2, sticky="ew")
        brand = tk.Frame(header, bg=COLORS["background"])
        brand.pack(side="left")
        self._label(brand, "CAMERA / STUDIO", 23, bold=True).pack(anchor="w")
        self._label(brand, "Your frame. Your controls. On your iPhone.", 10, COLORS["muted"]).pack(anchor="w", pady=(3, 0))
        tk.Label(header, textvariable=self.state_var, font=("Segoe UI", 12, "bold"),
                 bg=COLORS["background"], fg=COLORS["accent"]).pack(side="right")
        notebook = ttk.Notebook(self)
        notebook.grid(row=1, column=0, sticky="nsew", padx=(24, 12), pady=(0, 24))
        main = tk.Frame(notebook, bg=COLORS["panel"], padx=28, pady=24)
        notebook.add(main, text="  Recording controls  ")
        live = tk.Frame(notebook, bg=COLORS["panel"], padx=16, pady=16)
        notebook.add(live, text="  LIVE PREVIEW  ")
        self._build_preview(live)
        notebook.select(live)
        self._label(main, "RECORDING DASHBOARD", 12, COLORS["muted"], True).pack(anchor="w")
        self.recording_label = tk.Label(main, textvariable=self.recording_var, anchor="w",
            font=("Segoe UI", 20, "bold"), bg=COLORS["panel"], fg=COLORS["foreground"])
        self.recording_label.pack(fill="x", pady=(20, 4))
        tk.Label(main, textvariable=self.timer_var, anchor="w", font=("Consolas", 42, "bold"),
                 bg=COLORS["panel"], fg=COLORS["accent"]).pack(fill="x", pady=(0, 4))
        self._label(main, "Elapsed since recording was confirmed on this laptop", 10, COLORS["muted"]).pack(anchor="w")
        action = tk.Frame(main, bg=COLORS["panel"])
        action.pack(fill="x", pady=14)
        action.columnconfigure((0, 1), weight=1)
        self.start_btn = self._button(action, "START RECORDING", lambda: self._command("START"), primary=True)
        self.start_btn.configure(font=("Segoe UI", 14, "bold"), pady=14, bg="#c73350", fg="white")
        self.start_btn.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.stop_btn = self._button(action, "STOP & SAVE", lambda: self._command("STOP"))
        self.stop_btn.configure(font=("Segoe UI", 14, "bold"), pady=14)
        self.stop_btn.grid(row=0, column=1, sticky="ew", padx=(8, 0))
        self._label(main, "CAMERA SETTINGS", 12, COLORS["muted"], True).pack(anchor="w")
        quality = tk.Frame(main, bg=COLORS["panel"])
        quality.pack(fill="x", pady=(12, 16))
        self.mode_combo = ttk.Combobox(quality, textvariable=self.mode_var,
            values=("4K60", "4K30", "1080P60", "1080P30", "720P60", "720P30"), state="readonly", width=14,
            font=("Segoe UI", 12))
        self.mode_combo.bind("<<ComboboxSelected>>", lambda _event: setattr(self, "mode_dirty", True))
        self.mode_combo.pack(side="left", ipady=7)
        self.apply_btn = self._button(quality, "Apply quality", self._mode)
        self.apply_btn.pack(side="left", padx=12)
        tk.Label(main, textvariable=self.confirmed_quality, bg=COLORS["panel"], fg=COLORS["accent"],
            font=("Segoe UI", 11, "bold"), anchor="w", wraplength=600).pack(fill="x", pady=(0, 8))
        tk.Label(main, textvariable=self.clip_quality, bg=COLORS["panel"], fg=COLORS["muted"],
            font=("Segoe UI", 10), anchor="w", wraplength=600).pack(fill="x", pady=(0, 8))
        settings = tk.Frame(main, bg=COLORS["panel"])
        settings.pack(fill="x")
        self.back_btn = self._button(settings, "Back camera", lambda: self._command("CAM:BACK"))
        self.front_btn = self._button(settings, "Front camera", lambda: self._command("CAM:FRONT"))
        self.zoom1_btn = self._button(settings, "1× zoom", lambda: self._command("ZOOM:1"))
        self.zoom2_btn = self._button(settings, "2× zoom", lambda: self._command("ZOOM:2"))
        for i, w in enumerate((self.back_btn, self.front_btn, self.zoom1_btn, self.zoom2_btn)):
            w.grid(row=i // 2, column=i % 2, sticky="ew", padx=(0, 8), pady=(0, 8))
        settings.columnconfigure((0, 1), weight=1)
        tk.Label(main, textvariable=self.save_var, anchor="w", justify="left", wraplength=540,
            font=("Segoe UI", 12, "bold"), bg=COLORS["panel"], fg=COLORS["accent"]).pack(fill="x", pady=(16, 8))
        self._label(main, "Live video: open LIVE PREVIEW tab • Keep iPhone app open", 11, COLORS["muted"]).pack(anchor="w")
        side = tk.Frame(self, bg=COLORS["background"])
        side.grid(row=1, column=1, sticky="nsew", padx=(0, 24), pady=(0, 24))
        side.rowconfigure(1, weight=1)
        side.columnconfigure(0, weight=1)
        connect = tk.Frame(side, bg=COLORS["panel"], padx=20, pady=20)
        connect.grid(row=0, column=0, sticky="ew", pady=(0, 16))
        self._label(connect, "1  CONNECT YOUR iPHONE", 12, bold=True).pack(anchor="w", pady=(0, 12))
        self.devices_box = ttk.Combobox(connect, textvariable=self.device_var, state="readonly", font=("Segoe UI", 11))
        self.devices_box.pack(fill="x", ipady=7)
        self.scan_btn = self._button(connect, "Scan for iPhone", self._scan, primary=True)
        self.scan_btn.pack(fill="x", pady=10)
        self._label(connect, "6-digit PIN shown in the iPhone app", 11).pack(anchor="w")
        self.pin_field = tk.Entry(connect, textvariable=self.pin_var, show="•", bg="#0e1725", fg="white",
            insertbackground="white", font=("Segoe UI", 15), bd=0)
        self.pin_field.pack(fill="x", ipady=8, pady=(8, 12))
        row = tk.Frame(connect, bg=COLORS["panel"])
        row.pack(fill="x")
        self.connect_btn = self._button(row, "Connect", self._connect, primary=True)
        self.connect_btn.pack(side="left", fill="x", expand=True, padx=(0, 8))
        self.disconnect_btn = self._button(row, "Disconnect", self._disconnect)
        self.disconnect_btn.pack(side="left", fill="x", expand=True)
        log = tk.Frame(side, bg=COLORS["panel"], padx=20, pady=16)
        log.grid(row=1, column=0, sticky="nsew")
        self._label(log, "ACTIVITY & SAVE STATUS", 12, bold=True).pack(anchor="w")
        self.log_box = tk.Text(log, height=5, width=24, bg="#0c1524", fg="#d3e5f1", font=("Consolas", 10),
                               bd=0, state="disabled", wrap="word")
        self.log_box.pack(fill="both", expand=True, pady=12)
        tk.Label(log, textvariable=self.info_var, anchor="w", justify="left", wraplength=380,
                 bg=COLORS["panel"], fg=COLORS["foreground"], font=("Segoe UI", 11)).pack(fill="x")
        self.refresh_btn = self._button(log, "Refresh iPhone status", lambda: self._command("STATUS"))
        self.refresh_btn.pack(fill="x", pady=(12, 0))
        self._log("Open iPhone app → Scan → Enter PIN → Connect")
        self._set_controls()

    def _build_preview(self, parent):
        self._label(parent, "Live viewfinder", 21, bold=True).pack(anchor="w")
        self._label(parent, "Same Wi-Fi · Framing preview · Recordings stay on iPhone", 10, COLORS["muted"]).pack(anchor="w", pady=(4, 12))
        tk.Entry(parent, textvariable=self.preview_address, font=("Segoe UI", 11), bg="#0b1420", fg=COLORS["foreground"], insertbackground=COLORS["accent"], relief="flat", highlightthickness=1, highlightbackground=COLORS["border"]).pack(fill="x", ipady=8)
        controls = tk.Frame(parent, bg=COLORS["panel"])
        controls.pack(fill="x", pady=10)
        self._button(controls, "Connect preview", self._start_preview, primary=True).pack(side="left", padx=(0, 10))
        self._button(controls, "Stop preview", self._stop_preview).pack(side="left")
        tk.Label(parent, textvariable=self.preview_status, bg=COLORS["panel"], fg=COLORS["accent"],
                 font=("Segoe UI", 11), wraplength=600, justify="left").pack(fill="x", pady=(0, 10))
        self.preview_label = tk.Label(parent, bg="#050a12", fg="white", text="Your live viewfinder\n\nEnable Wi-Fi preview on iPhone, then connect above.",
                                     font=("Segoe UI", 14))
        self.preview_label.pack(fill="both", expand=True)
        live_controls = tk.Frame(parent, bg=COLORS["panel"])
        live_controls.pack(fill="x", pady=(10, 0))
        for column, (label, command) in enumerate((("Start", "START"), ("Stop & Save", "STOP"),
                ("Back", "CAM:BACK"), ("Front", "CAM:FRONT"), ("1×", "ZOOM:1"), ("2×", "ZOOM:2"))):
            live_controls.columnconfigure(column, weight=1)
            button = self._button(live_controls, label, lambda c=command: self._command(c))
            button.grid(row=0, column=column, sticky="ew", padx=2)
            self.live_buttons.append((button, command))
        live_quality = tk.Frame(parent, bg=COLORS["panel"])
        live_quality.pack(fill="x", pady=(8, 0))
        self.live_mode_combo = ttk.Combobox(live_quality, textvariable=self.mode_var, state="readonly", width=14,
            values=("4K60", "4K30", "1080P60", "1080P30", "720P60", "720P30"))
        self.live_mode_combo.pack(side="left", ipady=7)
        self.live_mode_combo.bind("<<ComboboxSelected>>", lambda _event: setattr(self, "mode_dirty", True))
        self.live_apply_btn = self._button(live_quality, "Apply quality", self._mode)
        self.live_apply_btn.pack(side="left", padx=8)
        self.live_buttons.append((self.live_apply_btn, "MODE"))
        tk.Label(parent, textvariable=self.confirmed_quality, bg=COLORS["panel"], fg=COLORS["accent"],
                 anchor="w", wraplength=600, font=("Segoe UI", 11, "bold")).pack(fill="x", pady=(8, 0))
        self._label(parent, "Preview stays low-resolution; recording quality is confirmed above.", 10, COLORS["muted"]).pack(anchor="w")
        tk.Label(parent, textvariable=self.clip_quality, bg=COLORS["panel"], fg=COLORS["accent"],
                 anchor="w", font=("Segoe UI", 10)).pack(fill="x", pady=(4, 0))
        self._label(parent, "Android: open the same link in Chrome. Enable Wi-Fi remote controls on iPhone.", 10, COLORS["muted"]).pack(anchor="w", pady=(10, 0))

    def _start_preview(self):
        self._stop_preview()
        try:
            self.preview_worker = PreviewWorker(self.preview_address.get())
        except ValueError as exc:
            self.preview_status.set(str(exc))
            return
        self.preview_status.set("Connecting to local iPhone preview…")
        self.preview_worker.thread.start()

    def _stop_preview(self):
        if self.preview_worker:
            self.preview_worker.stop()
            self.preview_worker = None
        self.preview_label.configure(image="", text="Preview stopped")
        self.preview_photo = None
        self.preview_status.set("Preview stopped • Bluetooth controls remain available")

    def _poll_preview(self):
        if self.preview_worker:
            for _ in range(2):
                try: kind, value = self.preview_worker.frames.get_nowait()
                except queue.Empty: break
                if kind == "camera_status":
                    self._handle_status(value)
                elif kind == "status":
                    self.preview_status.set(value)
                elif kind == "frame":
                    try:
                        with Image.open(io.BytesIO(value)) as source:
                            if source.width > 1280 or source.height > 1280:
                                raise ValueError("Preview dimensions exceed limit")
                            picture = source.copy()
                        picture.thumbnail((max(200, self.preview_label.winfo_width()), max(180, self.preview_label.winfo_height())))
                        self.preview_photo = ImageTk.PhotoImage(picture)
                        self.preview_label.configure(image=self.preview_photo, text="")
                        self.preview_last_frame = time.monotonic()
                        self.preview_status.set("LIVE · Local Wi-Fi preview · No audio")
                    except Exception:
                        self.preview_status.set("Invalid preview frame; reconnect using the iPhone link")
            if time.monotonic() - self.preview_last_frame > 3:
                self.preview_label.configure(image="", text="Waiting for live frames…")
                self.preview_photo = None
        self.after(100, self._poll_preview)

    def _tick(self):
        if self.recording_active and self.recording_since is not None:
            elapsed = int(time.monotonic() - self.recording_since)
            self.timer_var.set(f"{elapsed // 3600:02}:{elapsed // 60 % 60:02}:{elapsed % 60:02}")
        self.after(250, self._tick)

    def _recording_state(self, active):
        if active and not self.recording_active:
            self.recording_since = time.monotonic()
            self.timer_var.set("00:00:00")
            self.save_var.set("Recording on iPhone • Stop to finish and save")
        self.recording_active = active
        self.recording_var.set("RECORDING ON iPHONE" if active else "READY TO RECORD")
        self.recording_label.configure(fg=COLORS["red"] if active else COLORS["foreground"])
        self._set_controls()

    def _handle_status(self, value):
        fields = dict(field.split("=", 1) for field in value.removeprefix("STATUS:").split(";") if "=" in field) if value.startswith("STATUS:") else {}
        if "BUSY" in fields: self.busy_recording = fields["BUSY"] == "1"
        elif value in ("OK:STARTING", "OK:STOPPING"): self.busy_recording = True
        elif value == "REC:0": self.busy_recording = False
        if value.startswith("REC:1") or fields.get("REC") == "1":
            self._recording_state(True)
        elif value.startswith("REC:0") or fields.get("REC") == "0":
            self._recording_state(False)
        if value.startswith("OK:MODE:"):
            self.mode_dirty = False
            self.mode_var.set(value.removeprefix("OK:MODE:"))
            self.info_var.set("Quality applied on iPhone. Checking actual format…")
        if "MODE" in fields:
            if not self.mode_dirty: self.mode_var.set(fields["MODE"])
            self.confirmed_quality.set(f"Confirmed on iPhone: {fields['MODE']} · {fields.get('WIDTH', '?')} × {fields.get('HEIGHT', '?')} · {fields.get('FPS', '?')} FPS")
        if "CAM" in fields: self.camera_var.set(fields["CAM"])
        if fields.get("CAPS"):
            supported = fields["CAPS"].split(",")
            self.mode_combo.configure(values=supported)
            self.live_mode_combo.configure(values=supported)
            if self.mode_var.get() not in supported:
                self.mode_dirty = False
                self.mode_var.set(fields.get("MODE", supported[0]))
        if fields.get("LAST") and fields["LAST"] != "NONE":
            self.clip_quality.set("Verified saved file: " + fields["LAST"])
        if value.startswith("CLIP:"):
            self.clip_quality.set("Verified saved file: " + value.removeprefix("CLIP:"))
        if value.startswith("OK:CAM:"):
            side, _, mode = value.removeprefix("OK:CAM:").partition(";MODE=")
            self.camera_var.set(side)
            self.mode_dirty = False
            if mode: self.mode_var.set(mode)
        if fields.get("BUSY") == "1" and fields.get("REC") == "0":
            self.recording_var.set("STARTING / SAVING ON iPHONE…")
        self._set_controls()
        messages = {
            "OK:STARTING": "Starting… waiting for iPhone recording confirmation",
            "OK:STOPPING": "Stopping… waiting for file to finish",
            "OK:SAVED": "Saved in iPhone Files • Checking Photos save status",
            "SAVE:PHOTOS_PENDING": "File saved • Copying to Photos…",
            "SAVE:PHOTOS_OK": "SAVED TO PHOTOS / GALLERY + FILES",
            "SAVE:FILES_ONLY": "Saved in Files only • Allow Add Photos on iPhone, then retry import",
            "SAVE:PHOTOS_FAILED": "Photos save failed • Files copy is safe; retry on iPhone",
        }
        if value in messages:
            self.save_var.set(messages[value])
        if value.startswith("ERR:"):
            explanations = {
                "ERR:STOP_RECORDING_FIRST": "Stop & Save and wait for the file to finish before changing camera/quality.",
                "ERR:UNSUPPORTED_MODE": "This camera does not support that mode. Choose a mode reported by the iPhone.",
                "ERR:MODE_APPLY_FAILED": "iPhone could not apply the format/FPS. Check the confirmed format; try again while idle.",
                "ERR:AUTH_REQUIRED": "Reconnect Bluetooth and enter the current iPhone PIN.",
                "ERR:FOREGROUND_REQUIRED": "Keep iPhone BLE Camera open and the phone unlocked.",
            }
            self.info_var.set(explanations.get(value, value))
        if (value.startswith(("OK:MODE:", "OK:CAM:", "ERR:")) and self.authorized and self.connection_ok):
            self.worker.submit(self.worker.command("STATUS"))
        if value == "OK:AUTH":
            self.info_var.set("Connected. Apply quality, then Start recording.")
            self.worker.submit(self.worker.command("STATUS"))

    def _log(self, value):
        self.log_box.configure(state="normal")
        self.log_box.insert("end", f"{datetime.now():%H:%M:%S}  {value}\n")
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def _scan(self):
        self.scan_btn.configure(state="disabled")
        self.worker.submit(self.worker.scan())

    def _connect(self):
        index = self.devices_box.current()
        if index < 0 or index >= len(self.devices):
            messagebox.showinfo("Select iPhone", "Click 'Scan for iPhone' and choose a device.")
            return
        pin = self.pin_var.get().strip()
        if len(pin) != 6 or not pin.isascii() or not pin.isdigit():
            messagebox.showwarning("PIN", "Enter the 6-digit PIN shown in the iPhone app.")
            return
        self.connect_btn.configure(state="disabled")
        self.worker.submit(self.worker.connect(self.devices[index].address, pin))

    def _disconnect(self):
        self.worker.submit(self.worker.disconnect())

    def _command(self, command):
        if not self.authorized:
            messagebox.showinfo("Connect first", "Connect and enter your iPhone PIN first.")
            return
        if command in ("START", "STOP"):
            self.save_var.set("Sending command… waiting for iPhone")
        self.worker.submit(self.worker.command(command))

    def _mode(self):
        self._command(f"MODE:{self.mode_var.get()}")

    def _set_controls(self):
        can_send = self.connection_ok and self.authorized
        mode = "normal" if can_send else "disabled"
        for widget in (self.zoom1_btn, self.zoom2_btn, self.refresh_btn):
            widget.configure(state=mode)
        for widget in (self.apply_btn, self.back_btn, self.front_btn):
            widget.configure(state="normal" if can_send and not self.recording_active and not self.busy_recording else "disabled")
        self.start_btn.configure(state="normal" if can_send and not self.recording_active and not self.busy_recording else "disabled")
        self.stop_btn.configure(state="normal" if can_send else "disabled")
        for widget, command in self.live_buttons:
            allowed = can_send and (command == "STOP" or command.startswith("ZOOM:") or
                (not self.recording_active and not self.busy_recording))
            widget.configure(state="normal" if allowed else "disabled")
        self.connect_btn.configure(state="normal" if not self.connection_ok else "disabled")
        self.disconnect_btn.configure(state="normal" if self.connection_ok else "disabled")

    def _pump(self):
        for _ in range(30):
            try:
                event, value = self.events.get_nowait()
            except queue.Empty:
                break
            if event == "log":
                self._log(value)
            elif event == "error":
                self._log(f"ERROR: {value}")
                self.scan_btn.configure(state="normal")
                self._set_controls()
            elif event == "devices":
                self.devices = value
                labels = [f"{device.name}   [{device.address}]" for device in value]
                self.devices_box.configure(values=labels)
                if labels:
                    self.devices_box.current(0)
                else:
                    self.device_var.set("")
                self.scan_btn.configure(state="normal")
            elif event == "connected":
                self.connection_ok = bool(value)
                if not value:
                    self.authorized = False
                    self.recording_active = False
                    self.recording_since = None
                    self.recording_var.set("CONNECTION LOST")
                    self.save_var.set("Recording status unknown • Check the iPhone")
                self.state_var.set("CONNECTED" if value else "DISCONNECTED")
                self._set_controls()
            elif event == "authorized":
                self.authorized = bool(value)
                self.state_var.set("READY" if value else "PIN REJECTED")
                self._set_controls()
            elif event == "message":
                self._log(f"iPhone: {value}")
                self._handle_status(value)
        self.after(100, self._pump)

    def _close(self):
        self._stop_preview()
        try:
            self.worker.submit(self.worker.disconnect())
        except Exception:
            pass
        self.worker.loop.call_soon_threadsafe(self.worker.loop.call_later, 2, self.worker.loop.stop)
        self.destroy()


if __name__ == "__main__":
    CameraRemoteApp().mainloop()
