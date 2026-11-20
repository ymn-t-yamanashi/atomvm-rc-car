defmodule RcCarAtomvm.Provisioner do
  @moduledoc "Stores Wi-Fi credentials entered locally over the USB serial console."

  @nvs_namespace :atomvm
  @ssid_key :sta_ssid
  @psk_key :sta_psk
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
         :ok <- :esp.nvs_put_binary(@nvs_namespace, @ssid_key, ssid),
         :ok <- :esp.nvs_put_binary(@nvs_namespace, @psk_key, psk) do
      write(uart, "Wi-Fi and WebSocket settings saved to NVS.\r\n")
      :ok
    else
      {:error, reason} = error ->
        write(uart, "Wi-Fi setup failed: #{inspect(reason)}\r\n")
        error
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
    case :uart.read(uart, 1_000) do
      {:ok, data} ->
        case consume_input(uart, :erlang.iolist_to_binary(data), buffer, label) do
          {:line, value} -> finish_line(value, label)
          {:more, new_buffer} -> collect_line(uart, new_buffer, label, timeout)
        end

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

  defp consume_input(_uart, <<>>, buffer, _label), do: {:more, buffer}

  defp consume_input(_uart, <<byte, _rest::binary>>, buffer, _label)
       when byte in [10, 13],
       do: {:line, buffer}

  defp consume_input(uart, <<byte, rest::binary>>, <<>>, label) when byte in [8, 127] do
    consume_input(uart, rest, <<>>, label)
  end

  defp consume_input(uart, <<byte, rest::binary>>, buffer, label) when byte in [8, 127] do
    new_buffer = :erlang.binary_part(buffer, 0, byte_size(buffer) - 1)

    if echo_input?(label) do
      :uart.write(uart, <<8, 32, 8>>)
    end

    consume_input(uart, rest, new_buffer, label)
  end

  defp consume_input(uart, <<byte, rest::binary>>, buffer, label) do
    if echo_input?(label) do
      :uart.write(uart, <<byte>>)
    end

    consume_input(uart, rest, <<buffer::binary, byte>>, label)
  end

  defp finish_line(<<>>, label), do: {:error, {:empty_value, label}}
  defp finish_line(value, _label), do: {:ok, value}

  defp echo_input?("Wi-Fi password"), do: false
  defp echo_input?(_label), do: true

  defp write(uart, data), do: :uart.write(uart, data)
end
