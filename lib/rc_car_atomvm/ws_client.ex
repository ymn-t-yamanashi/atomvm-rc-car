defmodule RcCarAtomvm.WsClient do
  @moduledoc """
  Minimal WebSocket client for the device-to-Elixir server connection.

  The client supports plain `ws://` for a trusted LAN and `wss://` for a
  Cloud Run endpoint.  The initial TLS implementation uses `verify_none`
  because certificate verification is not available in the current firmware
  configuration.  Use this mode only for controlled experiments.
  """

  alias RcCarAtomvm.Config
  alias RcCarAtomvm.MotorController
  alias RcCarAtomvm.WebSocketFrame

  @accept_magic "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @recv_timeout 200

  @spec run() :: no_return()
  def run do
    case connect() do
      {:ok, connection, buffer} ->
        IO.puts("WebSocket connected")
        MotorController.stop()
        send_json(connection, %{type: "hello", role: "device", device_id: Config.device_id()})
        loop(connection, buffer)

      {:error, reason} ->
        IO.puts("WebSocket connection failed: #{inspect(reason)}")
        MotorController.stop()
        Process.sleep(3_000)
        run()
    end
  end

  defp connect do
    with {:ok, endpoint} <- Config.server_endpoint(),
         {:ok, connection} <- open_connection(endpoint),
         {:ok, key} <- handshake(connection, endpoint),
         {:ok, headers, buffer} <- recv_headers(connection) do
      expected = Base.encode64(:crypto.hash(:sha, key <> @accept_magic))

      if :binary.match(headers, expected) != :nomatch and
           :binary.match(headers, "HTTP/1.1 101") != :nomatch do
        {:ok, connection, buffer}
      else
        close_connection(connection)
        {:error, :invalid_websocket_accept}
      end
    end
  end

  defp open_connection(%{scheme: :ws, host: host, port: port}) do
    options = [:binary, active: false]

    case :gen_tcp.connect(:erlang.binary_to_list(host), port, options) do
      {:ok, socket} -> {:ok, %{socket: socket, transport: :gen_tcp}}
      error -> error
    end
  end

  defp open_connection(%{scheme: :wss, host: host, port: port}) do
    options = [
      :binary,
      active: false,
      verify: :verify_none,
      server_name_indication: :erlang.binary_to_list(host)
    ]

    with :ok <- start_ssl(),
         {:ok, socket} <- :ssl.connect(:erlang.binary_to_list(host), port, options) do
      {:ok, %{socket: socket, transport: :ssl}}
    end
  end

  defp start_ssl do
    case :ssl.start() do
      :ok -> :ok
      {:error, {:already_started, :ssl}} -> :ok
      error -> error
    end
  end

  defp handshake(connection, endpoint) do
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request = [
      "GET ",
      endpoint.path,
      " HTTP/1.1\r\n",
      "Host: ",
      host_header(endpoint),
      "\r\n",
      "Upgrade: websocket\r\n",
      "Connection: Upgrade\r\n",
      "Sec-WebSocket-Key: ",
      key,
      "\r\n",
      "Sec-WebSocket-Version: 13\r\n\r\n"
    ]

    case send_data(connection, request) do
      :ok -> {:ok, key}
      error -> error
    end
  end

  defp recv_headers(connection), do: recv_headers(connection, <<>>)

  defp recv_headers(connection, buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      :nomatch ->
        case recv_data(connection, 0, 5_000) do
          {:ok, chunk} -> recv_headers(connection, <<buffer::binary, chunk::binary>>)
          error -> error
        end

      {position, length} ->
        header_length = position + length
        <<headers::binary-size(header_length), rest::binary>> = buffer
        {:ok, headers, rest}
    end
  end

  defp loop(connection, buffer) do
    case WebSocketFrame.decode(buffer) do
      :more ->
        case recv_data(connection, 0, @recv_timeout) do
          {:ok, chunk} ->
            loop(connection, <<buffer::binary, chunk::binary>>)

          {:error, :timeout} ->
            loop(connection, buffer)

          {:error, reason} ->
            close(connection, reason)
        end

      {:error, reason} ->
        close(connection, reason)

      {:ok, frame, rest} ->
        case handle_frame(connection, frame) do
          :continue ->
            loop(connection, rest)

          :close ->
            close(connection, :server_closed)
        end
    end
  end

  defp handle_frame(connection, %{opcode: 1, payload: payload}) do
    case decode_json(payload) do
      {:ok, %{"type" => "motor_set", "left" => left, "right" => right}}
      when left in -1..1 and right in -1..1 ->
        :ok = MotorController.set(left, right)
        send_json(connection, %{type: "motor_state", left: left, right: right})
        :continue

      {:ok, %{"type" => "server_ready"}} ->
        :continue

      {:ok, %{"type" => "hello"}} ->
        :continue

      _ ->
        send_json(connection, %{type: "error", code: "invalid_message"})
        :continue
    end
  end

  defp handle_frame(connection, %{opcode: 9, payload: payload}) do
    :ok = send_data(connection, WebSocketFrame.encode_pong(payload))
    :continue
  end

  defp handle_frame(_connection, %{opcode: 8}), do: :close
  defp handle_frame(_connection, _frame), do: :continue

  defp send_json(connection, message) do
    payload = :json.encode(message)
    send_data(connection, WebSocketFrame.encode_text(IO.iodata_to_binary(payload)))
  end

  defp decode_json(payload) do
    {:ok, :json.decode(payload)}
  catch
    :error, _ -> {:error, :invalid_json}
  end

  defp host_header(%{host: host, port: port, scheme: scheme}) do
    if port == default_port(scheme) do
      host
    else
      <<host::binary, ":", :erlang.integer_to_binary(port)::binary>>
    end
  end

  defp default_port(:ws), do: 80
  defp default_port(:wss), do: 443

  defp send_data(%{transport: :gen_tcp, socket: socket}, data), do: :gen_tcp.send(socket, data)
  defp send_data(%{transport: :ssl, socket: socket}, data), do: :ssl.send(socket, data)

  defp recv_data(%{transport: :gen_tcp, socket: socket}, length, timeout),
    do: :gen_tcp.recv(socket, length, timeout)

  defp recv_data(%{transport: :ssl, socket: socket}, length, _timeout),
    do: :ssl.recv(socket, length)

  defp close_connection(%{transport: :gen_tcp, socket: socket}), do: :gen_tcp.close(socket)
  defp close_connection(%{transport: :ssl, socket: socket}), do: :ssl.close(socket)

  defp close(connection, reason) do
    IO.puts("WebSocket closed: #{inspect(reason)}")
    close_connection(connection)
    MotorController.stop()
    Process.sleep(3_000)
    run()
  end
end
