defmodule TradeImporter do
  @before_compile {TradeImporter.ReportParser, :setup}

  def parse(csv_path) do
    {_header, data} = csv_path
      |> File.read!()
      |> TradeImporter.CSVParser.parse_string
      |> TradeImporter.ReportParser.clean

    data
      |> TradeImporter.ReportParser.group_by_trade
      |> TradeImporter.ReportOrganizer.organize_trades_into_completed
      |> TradeImporter.ReportFormatter.format_for_eyes
  end
end
