defmodule Hierbautberlin.Importer do
  def import_all do
    Hierbautberlin.Importer.BerlinBebauungsplaene.import()
    Hierbautberlin.Importer.BerlinEconomy.import()
    Hierbautberlin.Importer.Infravelo.import()
    Hierbautberlin.Importer.MeinBerlin.import()
    Hierbautberlin.Importer.UVP.import()
  end
end
