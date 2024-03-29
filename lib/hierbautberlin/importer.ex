defmodule Hierbautberlin.Importer do
  def import_daily do
    Hierbautberlin.Importer.BerlinBebauungsplaene.import()
    Hierbautberlin.Importer.BerlinEconomy.import()
    Hierbautberlin.Importer.Infravelo.import()
    Hierbautberlin.Importer.MeinBerlin.import()
    Hierbautberlin.Importer.UVP.import()
    Hierbautberlin.Importer.DafMap.import()
    Hierbautberlin.Importer.BerlinerAmtsblatt.import_webpage()
  end

  def import_hourly do
    Hierbautberlin.Importer.BerlinPresse.import()
    Hierbautberlin.Importer.BerlinerAmtsblatt.import_folder()
  end
end
