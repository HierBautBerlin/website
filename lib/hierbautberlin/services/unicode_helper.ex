defmodule Hierbautberlin.Services.UnicodeHelper do
  def lower_case_letter?(character)

  def lower_case_letter?(nil) do
    false
  end

  def lower_case_letter?(character) do
    String.match?(character, ~r/^\p{Ll}/u)
  end

  def letter_or_digit?(character)

  def letter_or_digit?(nil) do
    false
  end

  def letter_or_digit?(character) do
    String.match?(character, ~r/^[\p{L}\p{Nd}]/u)
  end
end
