defmodule RcCarAtomvm.ConfigTest do
  use ExUnit.Case, async: true

  alias RcCarAtomvm.Config

  test "parses a local ws URL with an explicit port" do
    assert {:ok, %{scheme: :ws, host: "192.0.2.10", port: 4000, path: "/ws"}} =
             Config.parse_server_url("ws://192.0.2.10:4000/ws")
  end

  test "uses the default wss port and websocket path" do
    assert {:ok, %{scheme: :wss, host: "example.run.app", port: 443, path: "/ws"}} =
             Config.parse_server_url("wss://example.run.app")
  end

  test "accepts a custom websocket path" do
    assert {:ok, %{scheme: :wss, host: "example.run.app", port: 443, path: "/car/ws"}} =
             Config.parse_server_url("wss://example.run.app/car/ws")
  end

  test "rejects unsupported or malformed URLs" do
    assert {:error, :invalid_server_url} = Config.parse_server_url("http://example.run.app/ws")
    assert {:error, :invalid_server_url} = Config.parse_server_url("wss:///ws")
    assert {:error, :invalid_server_url} = Config.parse_server_url("wss://example.run.app:0/ws")
  end
end
