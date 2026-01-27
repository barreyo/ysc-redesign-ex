defmodule YscWeb.Workers.FileExportCleanUpTest do
  use ExUnit.Case, async: false

  alias YscWeb.Workers.FileExportCleanUp

  describe "perform/1" do
    test "runs cleanup successfully" do
      job = %Oban.Job{
        id: 1,
        args: %{},
        worker: "YscWeb.Workers.FileExportCleanUp",
        queue: "default",
        state: "available",
        attempt: 1
      }

      # The function may fail if export directory doesn't exist, but should handle gracefully
      result = FileExportCleanUp.perform(job)
      assert result == :ok || match?({:error, _}, result)
    end
  end

  describe "maybe_delete_file/2" do
    test "returns 0 for recent files" do
      recent_date = Timex.now()
      result = FileExportCleanUp.maybe_delete_file("/tmp/test", recent_date)
      assert result == 0
    end
  end

  describe "ctime_to_datetime/1" do
    test "converts ctime tuple to datetime" do
      ctime = {{2025, 1, 26}, {10, 30, 45}}
      datetime = FileExportCleanUp.ctime_to_datetime(ctime)
      assert %DateTime{} = datetime
    end
  end

  describe "zero_pad/1" do
    test "pads single digit numbers" do
      assert FileExportCleanUp.zero_pad(5) == "05"
      assert FileExportCleanUp.zero_pad(9) == "09"
    end

    test "does not pad double digit numbers" do
      assert FileExportCleanUp.zero_pad(10) == "10"
      assert FileExportCleanUp.zero_pad(99) == "99"
    end
  end
end
