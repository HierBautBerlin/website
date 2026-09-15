[
  # OTP 28 dialyzer reports opaque MapSet mismatches inside Ecto.Multi,
  # MapSet and Gettext calls. These are false positives in the libraries' specs.
  {"lib/hierbautberlin/accounts.ex", :call_without_opaque},
  {"lib/hierbautberlin_web/gettext.ex", :call_without_opaque},
  {"lib/hierbautberlin/geo_data/address_matcher.ex", :call_without_opaque},
  {"lib/hierbautberlin/geo_data/address_matcher.ex", :call_with_opaque}
]
