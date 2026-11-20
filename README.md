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

WSサーバーは`wss://rc.ymnbuild.org/ws`に固定しています。Wi-Fiパスワードはソースコードへ書きません。

1. AtomVMを書き込み、シリアルモニターを開く
2. 表示された入力欄へ、SSID・パスワードをローカル入力する

入力可能なシリアルコンソールの例：

```bash
screen /dev/cu.usbmodem21101 115200
```

`mix atomvm.esp32.monitor`は出力確認用で、入力はマイコンへ送られません。`screen`終了は`Ctrl-A`、`K`、`Y`の順です。

```text
wss://rc.ymnbuild.org/ws
```

SSIDとパスワードはESP32のNVSへ保存され、ソースコードには入りません。WSサーバーURLはファームウェアに固定されています。

既に設定済みの値を変更する場合は、起動後5秒以内に`r`＋Enterを入力すると再設定画面へ移ります。

### コマンドからWi-Fiを再設定する

パスワードをコマンドライン引数へ渡さず、ローカル入力で再設定できます。
スクリプトはパスワードをファイルへ保存しません。

```bash
python3 scripts/configure_wifi.py /dev/cu.usbmodem21101
```

実行後にマイコンをUSBから抜き差しすると、SSID入力とパスワード入力が順番に表示されます。
ポート名は環境に合わせて変更してください。macOSでは`ls /dev/cu.usb*`で確認できます。

NVSの値は暗号化されないため、強い秘密保管が必要な場合は別途検討が必要です。また、NVSの消去やフル消去を行うと再設定が必要になります。

WSモードでは、AtomVMが`wss://rc.ymnbuild.org/ws`へ接続し、次のメッセージを処理します。

```json
{"type":"motor_set","left":1,"right":1}
```

`left`と`right`は`-1`（後退）、`0`（停止）、`1`（前進）です。

切断・接続失敗時はモーターを停止します。接続中は、受信した`motor_set`の値をそのままGPIOへ反映します。

現在のAtomVM側のTLS接続は証明書検証を行わない実験的な構成です。公開環境で継続利用する前に、CA証明書と`verify_peer`対応を追加してください。
