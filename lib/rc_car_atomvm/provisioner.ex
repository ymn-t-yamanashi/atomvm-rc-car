defmodule RcCarAtomvm.Provisioner do
  @moduledoc "Stores Wi-Fi credentials entered locally over the USB serial console."

  @nvs_namespace :atomvm
  @ssid_key :sta_ssid
  @psk_key :sta_psk
  @server_namespace :rc_car
  @server_host_key :server_host
  @console_name "USB_SERIAL_JTAG"

  @spec reconfigure_requested?() :: boolean()
  def reconfigure_requested? do
    case :uart.open(@console_name, []) do
      uart when is_pid(uart) or is_port(uart) ->
        write(uart, "\r\nPress r + Enter within 5 seconds to reconfigure Wi-Fi.\r\n")
        requested = read_line(uart, "reconfigure", 5_000) in [{:ok, "r"}, {:ok, "R"}]
        :uart.close(uart)
        requested

      _ ->
        false
    end
  end

  @spec run() :: :ok | {:error, term()}
  def run do
    case :uart.open(@console_name, []) do
      uart when is_pid(uart) or is_port(uart) ->
        write(uart, "\r\nWi-Fi credentials are not configured.\r\n")
        write(uart, "Enter them locally. They will be stored in ESP32 NVS.\r\n")

        result = configure(uart)
        :uart.close(uart)
        result

      {:error, reason} ->
        IO.puts("USB serial setup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp configure(uart) do
    with {:ok, ssid} <- read_line(uart, "Wi-Fi SSID"),
         {:ok, psk} <- read_line(uart, "Wi-Fi password"),
         {:ok, server_host} <- read_server_host(uart),
         :ok <- :esp.nvs_put_binary(@nvs_namespace, @ssid_key, ssid),
         :ok <- :esp.nvs_put_binary(@nvs_namespace, @psk_key, psk),
         :ok <- :esp.nvs_put_binary(@server_namespace, @server_host_key, server_host) do
      write(uart, "Wi-Fi and WebSocket settings saved to NVS.\r\n")
      :ok
    else
      {:error, reason} = error ->
        write(uart, "Wi-Fi setup failed: #{inspect(reason)}\r\n")
        error
    end
  end

  defp read_server_host(uart) do
    with {:ok, value} <- read_line(uart, "WS server IPv4 address (this PC)"),
         {:ok, _address} <- :inet.parse_address(:erlang.binary_to_list(value)) do
      {:ok, value}
    else
      {:error, :einval} -> {:error, :invalid_server_host}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_server_host}
    end
  end

  defp read_line(uart, label) do
    write(uart, [label, ": "])
    collect_line(uart, <<>>, label, :wait)
  end

  defp read_line(uart, label, timeout) do
    write(uart, [label, ": "])
    collect_line(uart, <<>>, label, timeout)
  end

  defp collect_line(uart, buffer, label, timeout) do
    case line_end(buffer) do
      {:ok, position} ->
        value =
          buffer
          |> :erlang.binary_part(0, position)
          |> remove_line_ending()

        if value == <<>> do
          {:error, {:empty_value, label}}
        else
          {:ok, value}
        end

      :nomatch ->
        case :uart.read(uart, 1_000) do
          {:ok, data} ->
            collect_line(
              uart,
              <<buffer::binary, :erlang.iolist_to_binary(data)::binary>>,
              label,
              timeout
            )

          {:error, :timeout} ->
            if timeout == :wait do
              collect_line(uart, buffer, label, timeout)
            else
              {:error, :timeout}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp line_end(buffer) do
    case :binary.match(buffer, "\n") do
      {position, _length} ->
        {:ok, position}

      :nomatch ->
        case :binary.match(buffer, "\r") do
          {position, _length} -> {:ok, position}
          :nomatch -> :nomatch
        end
    end
  end

  defp write(uart, data), do: :uart.write(uart, data)

  defp remove_line_ending(<<>>), do: <<>>

  defp remove_line_ending(value) do
    length = byte_size(value)
    last_byte = :erlang.binary_part(value, length - 1, 1)

    if last_byte == "\n" or last_byte == "\r" do
      value
      |> :erlang.binary_part(0, length - 1)
      |> remove_line_ending()
    else
      value
    end
  end
end
