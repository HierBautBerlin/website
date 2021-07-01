defmodule Hierbautberlin.Importer do
  def import_daily do
    Hierbautberlin.Importer.BerlinBebauungsplaene.import()
    Hierbautberlin.Importer.BerlinEconomy.import()
    Hierbautberlin.Importer.Infravelo.import()
    Hierbautberlin.Importer.MeinBerlin.import()
    Hierbautberlin.Importer.UVP.import()
  end

  def import_hourly do
    Hierbautberlin.Importer.BerlinPresse.import()
  end
end
