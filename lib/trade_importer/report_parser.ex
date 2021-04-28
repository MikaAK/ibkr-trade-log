defmodule TradeImporter.ReportParser do
  alias TradeImporter.Row

  def setup(_) do
    NimbleCSV.define(
      TradeImporter.CSVParser,
      seperator: "\n",
      escape: "\""
    )
  end

  def clean(data) do
    [header | data] = filter_trades(data)

    {header, deserialize_timestamps(data)}
  end

  defp filter_trades(data) do
    Enum.filter(data, &(Row.record_type(&1) === "Trades" and Row.order_type(&1) in ["Trade", "DataDiscriminator"]))
  end

  defp deserialize_timestamps(data) do
    Enum.map(data, fn row ->
      update_in(
        row,
        [Access.at(6)],
        &(&1 |> String.replace(", ", "T") |> NaiveDateTime.from_iso8601!)
      )
    end)
  end

  def group_by_trade(data) do
    Enum.group_by(data, &Enum.at(&1, 5))
  end
end
