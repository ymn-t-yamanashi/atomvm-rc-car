defmodule RcCarAtomvm.WsClient do
  @moduledoc """
  Minimal WebSocket client for the device-to-Elixir server connection.

  The first network version intentionally uses plain `ws://` on a trusted LAN.
  TLS termination for the public XRift connection belongs at the server or
  reverse proxy layer.
  """

  alias RcCarAtomvm.Config
  alias RcCarAtomvm.MotorController
  alias RcCarAtomvm.WebSocketFrame

  @accept_magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @recv_timeout 200

  @spec run() :: no_return()
  def run do
    case connect() do
      {:ok, socket, buffer} ->
        IO.puts("WebSocket connected")
        MotorController.stop()
        send_json(socket, %{type: "hello", role: "device", device_id: Config.device_id()})
        loop(socket, buffer)

      {:error, reason} ->
        IO.puts("WebSocket connection failed: #{inspect(reason)}")
        MotorController.stop()
        Process.sleep(3_000)
        run()
    end
  end

  defp connect do
    options = [:binary, active: false]

    with {:ok, server_host} <- Config.server_host(),
         {:ok, socket} <- :gen_tcp.connect(server_host, Config.server_port(), options),
         {:ok, key} <- handshake(socket, server_host),
         {:ok, headers, buffer} <- recv_headers(socket) do
      expected = Base.encode64(:crypto.hash(:sha, key <> @accept_magic))

      if :binary.match(headers, expected) != :nomatch and
           :binary.match(headers, "HTTP/1.1 101") != :nomatch do
        {:ok, socket, buffer}
      else
        :gen_tcp.close(socket)
        {:error, :invalid_websocket_accept}
      end
    end
  end

  defp handshake(socket, server_host) do
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request = [
      "GET ",
      Config.server_path(),
      " HTTP/1.1\r\n",
      "Host: ",
      host_header(server_host),
      "\r\n",
      "Upgrade: websocket\r\n",
      "Connection: Upgrade\r\n",
      "Sec-WebSocket-Key: ",
      key,
      "\r\n",
      "Sec-WebSocket-Version: 13\r\n\r\n"
    ]

    case :gen_tcp.send(socket, request) do
      :ok -> {:ok, key}
      error -> error
    end
  end

  defp recv_headers(socket), do: recv_headers(socket, <<>>)

  defp recv_headers(socket, buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      :nomatch ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, chunk} -> recv_headers(socket, <<buffer::binary, chunk::binary>>)
          error -> error
        end

      {position, length} ->
        header_length = position + length
        <<headers::binary-size(header_length), rest::binary>> = buffer
        {:ok, headers, rest}
    end
  end

  defp loop(socket, buffer) do
    case WebSocketFrame.decode(buffer) do
      :more ->
        case :gen_tcp.recv(socket, 0, @recv_timeout) do
          {:ok, chunk} ->
            loop(socket, <<buffer::binary, chunk::binary>>)

          {:error, :timeout} ->
            loop(socket, buffer)

          {:error, reason} ->
            close(socket, reason)
        end

      {:error, reason} ->
        close(socket, reason)

      {:ok, frame, rest} ->
        case handle_frame(socket, frame) do
          :continue ->
            loop(socket, rest)

          :close ->
            close(socket, :server_closed)
        end
    end
  end

  defp handle_frame(socket, %{opcode: 1, payload: payload}) do
    case decode_json(payload) do
      {:ok, %{"type" => "motor_set", "left" => left, "right" => right}}
      when left in -1..1 and right in -1..1 ->
        :ok = MotorController.set(left, right)
        send_json(socket, %{type: "motor_state", left: left, right: right})
        :continue

      {:ok, %{"type" => "server_ready"}} ->
        :continue

      {:ok, %{"type" => "hello"}} ->
        :continue

      _ ->
        send_json(socket, %{type: "error", code: "invalid_message"})
        :continue
    end
  end

  defp handle_frame(socket, %{opcode: 9, payload: payload}) do
    :gen_tcp.send(socket, WebSocketFrame.encode_pong(payload))
    :continue
  end

  defp handle_frame(_socket, %{opcode: 8}), do: :close

  defp handle_frame(_socket, _frame), do: :continue

  defp send_json(socket, message) do
    payload = :json.encode(message)
    :gen_tcp.send(socket, WebSocketFrame.encode_text(IO.iodata_to_binary(payload)))
  end

  defp decode_json(payload) do
    {:ok, :json.decode(payload)}
  catch
    :error, _ -> {:error, :invalid_json}
  end

  defp host_header(server_host) do
    server_host
    |> :inet.ntoa()
    |> List.to_string()
  end

  defp close(socket, reason) do
    IO.puts("WebSocket closed: #{inspect(reason)}")
    :gen_tcp.close(socket)
    MotorController.stop()
    Process.sleep(3_000)
    run()
  end
end
