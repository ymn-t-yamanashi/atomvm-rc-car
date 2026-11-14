defmodule RcCarAtomvm.MotorController do
  @moduledoc """
  Fixed-speed two-motor controller for the L298N direction inputs.

  ENA and ENB are kept enabled by jumpers on the L298N module, so this
  controller only drives the four direction GPIOs.
  """

  @left_in1 1
  @left_in2 2
  @right_in1 3
  @right_in2 6

  @type direction :: -1 | 0 | 1

  @spec init() :: :ok
  def init do
    Enum.each([@left_in1, @left_in2, @right_in1, @right_in2], fn pin ->
      :ok = :gpio.set_pin_mode(pin, :output)
    end)

    stop()
  end

  @spec set(direction(), direction()) :: :ok
  def set(left, right) when left in -1..1 and right in -1..1 do
    write_side(left, @left_in1, @left_in2)
    write_side(right, @right_in1, @right_in2)
    IO.puts("Motors: left=#{left} right=#{right}")
    :ok
  end

  @spec stop() :: :ok
  def stop, do: set(0, 0)

  defp write_side(direction, in1, in2) do
    {first, second} =
      case direction do
        1 -> {:high, :low}
        -1 -> {:low, :high}
        0 -> {:low, :low}
      end

    :ok = :gpio.digital_write(in1, first)
    :ok = :gpio.digital_write(in2, second)
  end
end
