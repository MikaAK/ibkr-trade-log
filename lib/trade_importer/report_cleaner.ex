defmodule TradeImporter.ReportCleaner do
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
    Enum.filter(data, &(row_record_type(&1) === "Trades" and row_order_type(&1) in ["Trade", "DataDiscriminator"]))
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

  def format_for_eyes(data, headings) do
  end

  def split_full_trades(data) do
    Enum.map(data, fn {order_strike_exp, trades} ->
      trades = Enum.sort_by(trades, &row_trade_time/1, :asc)
      {completed, opened} = split_completed_and_opened_trades(trades)

      {order_strike_exp, %{
        completed: Enum.reverse(completed),
        opened: Enum.reverse(opened)
      }}
    end)
  end

  defp split_completed_and_opened_trades(trades) do
    Enum.reduce(trades, {[], []}, fn trade, {completed, opened} ->
      trade = update_row_trade_position(trade, trade |> row_trade_position() |> maybe_parse_int)
      position = row_trade_position(trade)

      cond do
        position === 0 -> {completed, opened}
        row_realized_profit(trade) === "0" -> {completed, [trade | opened]}
        position < 0 -> complete_long_trade(trade, completed, opened)
        position > 0 -> complete_short_trade(trade, completed, opened)
      end
    end)
  end

  defp complete_long_trade(trade, completed, []) do
    {[%{start: :unknown, end: trade} | completed], []}
  end

  defp complete_long_trade(trade, completed, opened) do
    {completed_trade, new_opened} = opened
      |> Enum.reverse
      |> Enum.reduce_while({%{end: trade}, opened}, fn (opened_trade, {acc_trade, acc_opened}) ->
        opened_position = row_trade_position(opened_trade)
        trade_position = row_trade_position(trade)
        position_delta = opened_position + trade_position
        completed_trade = Map.update(acc_trade, :start, [opened_trade], &[opened_trade | &1])

        cond do
          position_delta === 0 ->
            {:halt, {completed_trade, tl(acc_opened)}}

          position_delta > 0 ->
            opened_trade = update_row_trade_position(opened_trade, position_delta)

            {:halt, {completed_trade, [opened_trade | tl(acc_opened)]}}

          position_delta < 0 ->
            {:continue, {completed_trade, tl(acc_opened)}}
        end
      end)

    {
      [update_in(completed_trade.start, &Enum.reverse/1) | completed],
      Enum.reverse(new_opened)
    }
  end

  defp complete_short_trade(trade, completed, []) do
    {[%{start: :unknown, end: trade} | completed], []}
  end

  defp complete_short_trade(trade, completed, opened) do
    {completed_trade, new_opened} = opened
      |> Enum.reverse
      |> Enum.reduce_while({%{end: trade}, opened}, fn (opened_trade, {acc_trade, acc_opened}) ->
        opened_position = row_trade_position(opened_trade)
        trade_position = row_trade_position(trade)
        position_delta = opened_position + trade_position
        completed_trade = Map.update(acc_trade, :start, [opened_trade], &[opened_trade | &1])

        cond do
          position_delta === 0 ->
            {:halt, {completed_trade, tl(acc_opened)}}

          position_delta < 0 ->
            opened_trade = update_row_trade_position(opened_trade, position_delta)

            {:halt, {completed_trade, [opened_trade | tl(acc_opened)]}}

          position_delta > 0 ->
            {:continue, {completed_trade, tl(acc_opened)}}
        end
      end)

    {
      [update_in(completed_trade.start, &Enum.reverse/1) | completed],
      Enum.reverse(new_opened)
    }
  end

  defp update_row_trade_position(row, position), do: put_in(row, [Access.at(8)], position)
  defp row_trade_position(row), do: row |> Enum.at(8) |> maybe_parse_int
  defp row_realized_profit(row), do: Enum.at(row, 14)
  defp row_trade_time(row), do: Enum.at(row, 6)
  defp row_record_type(row), do: Enum.at(row, 0)
  defp row_order_type(row), do: Enum.at(row, 2)

  defp maybe_parse_int(str) when is_binary(str), do: str |> Integer.parse |> elem(0)
  defp maybe_parse_int(int), do: int
end
