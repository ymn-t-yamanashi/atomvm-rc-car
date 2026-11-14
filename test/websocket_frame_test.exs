defmodule RcCarAtomvm.WebSocketFrameTest do
  use ExUnit.Case, async: true

  alias RcCarAtomvm.WebSocketFrame

  test "encodes a client text frame and decodes a server text frame" do
    encoded = WebSocketFrame.encode_text("hello")
    assert <<0x81, second, _mask::binary-size(4), _payload::binary-size(5)>> = encoded
    assert second >= 0x80

    server_frame = <<0x81, 5, "hello">>
    assert {:ok, %{opcode: 1, payload: "hello"}, <<>>} = WebSocketFrame.decode(server_frame)
  end

  test "decodes a server frame with an extended payload length" do
    payload = :binary.copy("x", 126)
    frame = <<0x81, 126, 126::16, payload::binary>>
    assert {:ok, %{opcode: 1, payload: ^payload}, <<>>} = WebSocketFrame.decode(frame)
  end

  test "decodes a masked frame" do
    assert {:ok, %{opcode: 1, payload: "hello"}, <<>>} =
             WebSocketFrame.decode(<<0x81, 0x85, 1, 2, 3, 4, "igohn">>)
  end
end
