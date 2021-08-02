defmodule Hierbautberlin.Services.UnicodeHelper do
  def is_character_lower_case_letter?(character)

  def is_character_lower_case_letter?(nil) do
    false
  end

  def is_character_lower_case_letter?(character) do
    Enum.member?(
      [:Ll],
      character |> Unicode.category() |> List.first()
    )
  end

  def is_character_letter_or_digit?(character)

  def is_character_letter_or_digit?(nil) do
    false
  end

  def is_character_letter_or_digit?(character) do
    Enum.member?(
      [:L, :Ll, :Lm, :Lo, :Lt, :Lu, :Nd],
      character |> Unicode.category() |> List.first()
    )
  end
end
