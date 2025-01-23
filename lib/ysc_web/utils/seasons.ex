defmodule YscWeb.Seasons do
  @doc """
  Determines the current season based on the date.
  """

  @winter_start {11, 1}
  @winter_end {4, 1}

  def get_current_season() do
    get_season(Date.utc_today())
  end

  def get_season(date) do
    {month, day} = {date.month, date.day}

    cond do
      {month, day} >= @winter_start or {month, day} <= @winter_end -> :winter
      true -> :summer
    end
  end
end
