#!/usr/bin/env python3
"""Provision Wi-Fi credentials over the XIAO USB serial console.

The credentials are read locally and sent directly to the firmware. They are
never written to a file or included in a command line argument.
"""

from __future__ import annotations

import getpass
import os
import select
import sys
import termios
import time


BAUD = termios.B115200
BOOT_PROMPT = b"Press r + Enter within 5 seconds"
SSID_PROMPT = b"Wi-Fi SSID:"
PASSWORD_PROMPT = b"Wi-Fi password:"
SAVED_MESSAGE = b"Wi-Fi and WebSocket settings saved to NVS."


def configure_serial(fd: int) -> None:
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
    attrs[3] = 0
    attrs[4] = BAUD
    attrs[5] = BAUD
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 5
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


class SerialLink:
    def __init__(self, port: str) -> None:
        self.port = port
        self.fd: int | None = None

    def open(self) -> None:
        if self.fd is not None:
            return
        fd = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        try:
            configure_serial(fd)
        except (OSError, termios.error):
            os.close(fd)
            raise
        self.fd = fd

    def close(self) -> None:
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def read_until(self, marker: bytes, timeout: float) -> bytes:
        deadline = time.monotonic() + timeout
        buffer = bytearray()

        while time.monotonic() < deadline:
            try:
                self.open()
            except (OSError, termios.error):
                time.sleep(0.25)
                continue

            remaining = max(0.0, deadline - time.monotonic())
            try:
                ready, _, _ = select.select([self.fd], [], [], min(0.5, remaining))
                if not ready:
                    continue

                chunk = os.read(self.fd, 4096)
            except (OSError, ValueError):
                self.close()
                continue

            if not chunk:
                self.close()
                continue
            buffer.extend(chunk)
            if marker in buffer:
                return bytes(buffer)

        raise TimeoutError(marker.decode("ascii", errors="replace"))

    def send_line(self, value: str) -> None:
        self.open()
        try:
            os.write(self.fd, value.encode("utf-8") + b"\r\n")
        except (OSError, termios.error):
            self.close()
            self.open()
            os.write(self.fd, value.encode("utf-8") + b"\r\n")


def main() -> int:
    port = sys.argv[1] if len(sys.argv) > 1 else "/dev/cu.usbmodem21101"

    if len(sys.argv) > 2:
        print(f"使い方: {sys.argv[0]} [シリアルポート]", file=sys.stderr)
        return 2

    print(f"接続先: {port}")
    print("マイコンをUSBから抜き差しして、起動を開始してください。")
    print("パスワードは保存されず、画面にも表示されません。")

    link = SerialLink(port)
    try:
        link.read_until(BOOT_PROMPT, 30.0)
        link.send_line("r")
        link.close()
        link.read_until(SSID_PROMPT, 8.0)

        ssid = input("新しいSSID: ")
        if not ssid:
            print("SSIDが空です。", file=sys.stderr)
            return 1
        link.send_line(ssid)

        link.read_until(PASSWORD_PROMPT, 8.0)
        password = getpass.getpass("新しいパスワード: ")
        if not password:
            print("パスワードが空です。", file=sys.stderr)
            return 1
        link.send_line(password)

        link.read_until(SAVED_MESSAGE, 12.0)
        print("Wi-Fi設定をESP32のNVSへ保存しました。")
        print("マイコンが新しいWi-Fiへ接続するまで待ってください。")
        return 0
    except TimeoutError as error:
        print(f"入力待ちがタイムアウトしました: {error}", file=sys.stderr)
        print("マイコンを抜き差しして、もう一度実行してください。", file=sys.stderr)
        return 1
    except (OSError, termios.error) as error:
        print(f"シリアル通信に失敗しました: {error}", file=sys.stderr)
        return 1
    finally:
        link.close()


if __name__ == "__main__":
    raise SystemExit(main())
