defmodule TradeImporter do
  @before_compile {TradeImporter.ReportCleaner, :setup}

  def parse(csv_path) do
    csv_path
      |> File.read!()
      |> TradeImporter.CSVParser.parse_string
      |> TradeImporter.ReportCleaner.clean
  end
end
