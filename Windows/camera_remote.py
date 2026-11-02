"""iPhone BLE Camera Remote — Windows laptop GUI. Local commands only.

Requires a matching iOS companion app in the foreground and Bluetooth LE.
Video stays on the iPhone; it is never transmitted over Bluetooth.
"""
from __future__ import annotations

import asyncio
import queue
import threading
import tkinter as tk
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
    "background": "#101827", "panel": "#192539", "border": "#35465f",
    "foreground": "#f0f5fb", "muted": "#a6b5c8", "accent": "#55e6ae",
    "blue": "#399ceb", "warning": "#edb65d", "red": "#ec6d7a",
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
        self.loop.run_forever()

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


class CameraRemoteApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("iPhone 4K BLE Camera — Laptop Remote")
        self.geometry("845x720")
        self.minsize(750, 655)
        self.configure(bg=COLORS["background"])
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
        self._build_ui()
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
                           fg="white", activebackground="#428dc7",
                           activeforeground="white", bd=0, padx=16, pady=9,
                           cursor="hand2", font=("Segoe UI", 10, "bold"), width=width)
        return button

    def _build_ui(self):
        tk.Label(self, text="iPHONE CAMERA  /  BLE REMOTE", fg=COLORS["accent"],
                 bg=COLORS["background"], font=("Segoe UI", 10, "bold")).pack(anchor="w", padx=24, pady=(18, 0))
        tk.Label(self, text="Record on iPhone. Control from laptop.",
                 fg=COLORS["foreground"], bg=COLORS["background"],
                 font=("Segoe UI", 19, "bold")).pack(anchor="w", padx=22, pady=(1, 14))

        device_panel = self._frame(self)
        self._label(device_panel, "1  /  BLUETOOTH CONNECTION", 11, COLORS["muted"], True).pack(anchor="w", pady=(0, 12))
        row = tk.Frame(device_panel, bg=COLORS["panel"])
        row.pack(fill="x")
        self.devices_box = ttk.Combobox(row, textvariable=self.device_var, state="readonly", width=48)
        self.devices_box.pack(side="left", fill="x", expand=True, padx=(0, 8))
        self.scan_btn = self._button(row, "Scan for iPhone", self._scan, primary=True)
        self.scan_btn.pack(side="left")
        row2 = tk.Frame(device_panel, bg=COLORS["panel"])
        row2.pack(fill="x", pady=(12, 0))
        self._label(row2, "iPhone 6-digit PIN").pack(side="left", padx=(0, 10))
        self.pin_field = tk.Entry(row2, textvariable=self.pin_var, width=12, show="•",
                                  bg="#0e1725", fg="white", insertbackground="white",
                                  font=("Segoe UI", 12), bd=0)
        self.pin_field.pack(side="left", ipady=6)
        self.connect_btn = self._button(row2, "Connect", self._connect, primary=True)
        self.connect_btn.pack(side="left", padx=(12, 8))
        self.disconnect_btn = self._button(row2, "Disconnect", self._disconnect)
        self.disconnect_btn.pack(side="left")

        record_panel = self._frame(self)
        self._label(record_panel, "2  /  VIDEO QUALITY", 11, COLORS["muted"], True).pack(anchor="w", pady=(0, 10))
        quality_row = tk.Frame(record_panel, bg=COLORS["panel"])
        quality_row.pack(fill="x")
        self.mode_combo = ttk.Combobox(quality_row, textvariable=self.mode_var,
                                        values=("4K60", "4K30", "1080P60", "1080P30", "720P60", "720P30"),
                                        state="readonly", width=20)
        self.mode_combo.pack(side="left", padx=(0, 10), ipady=4)
        self.apply_btn = self._button(quality_row, "Apply Quality", self._mode)
        self.apply_btn.pack(side="left")
        self._label(quality_row, "Only supported modes will work", 10, COLORS["muted"]).pack(side="left", padx=13)
        cam_row = tk.Frame(record_panel, bg=COLORS["panel"])
        cam_row.pack(fill="x", pady=(12, 0))
        self._label(cam_row, "Camera:").pack(side="left", padx=(0, 9))
        self.back_btn = self._button(cam_row, "Back", lambda: self._command("CAM:BACK"))
        self.back_btn.pack(side="left", padx=(0, 5))
        self.front_btn = self._button(cam_row, "Front", lambda: self._command("CAM:FRONT"))
        self.front_btn.pack(side="left")
        self._label(cam_row, "Zoom:").pack(side="left", padx=(30, 9))
        self.zoom1_btn = self._button(cam_row, "1×", lambda: self._command("ZOOM:1"))
        self.zoom1_btn.pack(side="left", padx=(0, 5))
        self.zoom2_btn = self._button(cam_row, "2×", lambda: self._command("ZOOM:2"))
        self.zoom2_btn.pack(side="left")

        action_panel = self._frame(self)
        self._label(action_panel, "3  /  RECORDING", 11, COLORS["muted"], True).pack(anchor="w", pady=(0, 10))
        buttons = tk.Frame(action_panel, bg=COLORS["panel"])
        buttons.pack(fill="x")
        self.start_btn = self._button(buttons, "●  START RECORDING", lambda: self._command("START"), primary=True, width=22)
        self.start_btn.pack(side="left", padx=(0, 12))
        self.stop_btn = self._button(buttons, "■  STOP RECORDING", lambda: self._command("STOP"), width=22)
        self.stop_btn.pack(side="left")
        self.refresh_btn = self._button(buttons, "Refresh status", lambda: self._command("STATUS"))
        self.refresh_btn.pack(side="right")
        tk.Label(action_panel, textvariable=self.recording_var, bg=COLORS["panel"],
                 fg=COLORS["accent"], font=("Segoe UI", 12, "bold")).pack(anchor="w", pady=(12, 0))
        tk.Label(action_panel, textvariable=self.info_var, bg=COLORS["panel"],
                 fg=COLORS["muted"], font=("Segoe UI", 9)).pack(anchor="w", pady=(4, 0))

        status_panel = self._frame(self)
        top = tk.Frame(status_panel, bg=COLORS["panel"])
        top.pack(fill="x")
        self._label(top, "DEVICE LOG", 10, COLORS["muted"], True).pack(side="left")
        tk.Label(top, textvariable=self.state_var, bg=COLORS["panel"], fg=COLORS["warning"],
                 font=("Segoe UI", 10, "bold")).pack(side="right")
        self.log_box = tk.Text(status_panel, height=7, bg="#0c1524", fg="#d3e5f1",
                               font=("Consolas", 9), insertbackground="white", bd=0,
                               state="disabled", wrap="word")
        self.log_box.pack(fill="both", expand=True, pady=(8, 0))
        self._log("Ready. Open the iPhone companion app, then scan.")
        self._set_controls()

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
        self.worker.submit(self.worker.command(command))

    def _mode(self):
        self._command(f"MODE:{self.mode_var.get()}")

    def _set_controls(self):
        can_send = self.connection_ok and self.authorized
        mode = "normal" if can_send else "disabled"
        for widget in (self.start_btn, self.stop_btn, self.apply_btn, self.back_btn,
                       self.front_btn, self.zoom1_btn, self.zoom2_btn, self.refresh_btn):
            widget.configure(state=mode)
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
                    self.recording_var.set("Recording status unknown (disconnected)")
                self.state_var.set("CONNECTED" if value else "DISCONNECTED")
                self._set_controls()
            elif event == "authorized":
                self.authorized = bool(value)
                self.state_var.set("READY" if value else "PIN REJECTED")
                self._set_controls()
            elif event == "message":
                self._log(f"iPhone: {value}")
                if value.startswith("REC:1") or "REC=1" in value:
                    self.recording_var.set("● Recording on iPhone")
                elif value.startswith("REC:0") or "REC=0" in value:
                    self.recording_var.set("Not recording")
                elif value.startswith("OK:MODE:"):
                    self.mode_var.set(value.removeprefix("OK:MODE:"))
                elif value.startswith("ERR:"):
                    self.info_var.set(value)
                if value == "OK:AUTH":
                    self.info_var.set("Authenticated; iPhone camera ready for commands")
        self.after(100, self._pump)

    def _close(self):
        try:
            self.worker.submit(self.worker.disconnect())
        except Exception:
            pass
        self.worker.loop.call_later(2, self.worker.loop.stop)
        self.destroy()


if __name__ == "__main__":
    CameraRemoteApp().mainloop()
