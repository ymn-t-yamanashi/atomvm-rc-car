defmodule RcCarAtomvm do
  @moduledoc """
  AtomVM entrypoint for the XIAO ESP32-S3 RC car controller.

  Wi-Fi credentials are provisioned locally over USB and stored in ESP32 NVS.
  """

  alias RcCarAtomvm.Config
  alias RcCarAtomvm.MotorController
  alias RcCarAtomvm.Provisioner
  alias RcCarAtomvm.WsClient

  @spec start() :: no_return()
  def start do
    MotorController.init()

    if Provisioner.reconfigure_requested?() do
      configure_and_start()
    else
      ws_mode()
    end
  end

  defp configure_and_start do
    case Provisioner.run() do
      :ok ->
        ws_mode()

      {:error, _reason} ->
        Process.sleep(2_000)
        ws_mode()
    end
  end

  defp ws_mode do
    case Config.wifi() do
      {:ok, wifi_config} ->
        case :network.wait_for_sta(wifi_config, 15_000) do
          {:ok, address} ->
            IO.puts("Wi-Fi connected: #{inspect(address)}")
            WsClient.run()

          {:error, reason} ->
            IO.puts("Wi-Fi connection failed: #{inspect(reason)}")
            MotorController.stop()
            stop_network()
            Process.sleep(5_000)
            ws_mode()
        end

      {:error, :missing_wifi_credentials} ->
        MotorController.stop()

        configure_and_start()
    end
  end

  defp stop_network do
    try do
      _ = :network.stop()
      :ok
    catch
      _, _ -> :ok
    end
  end
end
