# AtomVM RC Car Firmware

XIAO ESP32-S3 + Grove Shield for XIAO向けのAtomVM/Elixirファームウェアです。

## 現在の構成

- Grove Shield for XIAO
- XIAO ESP32-S3
- L298Nモータードライバ
- 左右2個のDCモーター
- ENA/ENBジャンパー接続
- D0/D1/D2/D5による方向制御

モーター電源はGrove Shieldから取らず、L298Nへ別電源を接続します。

## 3つのPJの関係

このPJは、XIAO ESP32-S3上で動作する車体側のAtomVM/Elixirファームウェアです。

- [`rc-world`](https://github.com/ymn-t-yamanashi/rc-world)：XRift内の運転席とWASD・カーソル操作を提供します。
- [`ws-server`](https://github.com/ymn-t-yamanashi/rc-ws-server)：PC上でXRiftとAtomVMのWebSocketを中継します。
- [`atomvm-rc-car`](https://github.com/ymn-t-yamanashi/atomvm-rc-car)（このPJ）：WSで受信した`motor_set`をGPIOへ反映します。

通信経路は次のとおりです。

```text
XRift rc-world ⇄ WebSocket /ws ⇄ PC上のws-server ⇄ WebSocket ⇄ XIAO AtomVM
                                                                        ↓
                                                             GPIO → L298N → 左右モーター
```

`motor_set`の`left`と`right`は、`-1`（後退）、`0`（停止）、`1`（前進）です。
通常は、WSサーバーを起動してからAtomVMを起動し、最後にXRiftワールドへ接続します。

## セットアップ

```bash
mix deps.get
mix atomvm.check
mix test
mix atomvm.packbeam
```

AtomVMのESP32-S3 Elixirイメージを一度書き込んだ後、アプリケーションを書き込みます。

```bash
mix atomvm.esp32.install --chip esp32s3
mix atomvm.esp32.flash
mix atomvm.esp32.monitor
```

## WSモード

`lib/rc_car_atomvm/config.ex`にはWi-FiパスワードやWSサーバーアドレスを書きません。

1. AtomVMを書き込み、シリアルモニターを開く
2. 表示された入力欄へ、SSID・パスワード・このPCのWSサーバーIPv4アドレスをローカル入力する

入力可能なシリアルコンソールの例：

```bash
screen /dev/cu.usbmodem21101 115200
```

`mix atomvm.esp32.monitor`は出力確認用で、入力はマイコンへ送られません。`screen`終了は`Ctrl-A`、`K`、`Y`の順です。

このPCのWi-Fi側アドレスを確認し、マイコンと同じLANに接続しているアドレスを入力してください。

SSID・パスワード・WSサーバーIPv4アドレスはESP32のNVSへ保存され、ソースコードには入りません。次回以降は自動的にNVSから読み出します。

既に設定済みの値を変更する場合は、起動後5秒以内に`r`＋Enterを入力すると再設定画面へ移ります。

NVSの値は暗号化されないため、強い秘密保管が必要な場合は別途検討が必要です。また、NVSの消去やフル消去を行うと再設定が必要になります。

WSモードでは、AtomVMが`ws://<server>:4000/ws`へ接続し、次のメッセージを処理します。

```json
{"type":"motor_set","left":1,"right":1}
```

`left`と`right`は`-1`（後退）、`0`（停止）、`1`（前進）です。

切断・接続失敗時はモーターを停止します。接続中は、受信した`motor_set`の値をそのままGPIOへ反映します。

初期版のAtomVM側は信頼できるLAN内の`ws://`を対象にしています。XRiftを公開HTTPSで動かす場合の`wss://`終端はWSサーバーまたはリバースプロキシ側で行います。
