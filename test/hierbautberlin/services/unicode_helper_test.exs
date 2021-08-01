defmodule Hierbautberlin.Services.UnicodeHelperTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Services.UnicodeHelper

  describe "is_character_lower_case_letter?/1" do
    test "returns the correct data" do
      assert UnicodeHelper.is_character_lower_case_letter?("a")
      assert UnicodeHelper.is_character_lower_case_letter?("z")
      assert UnicodeHelper.is_character_lower_case_letter?("ö")
      assert UnicodeHelper.is_character_lower_case_letter?("ß")

      refute UnicodeHelper.is_character_lower_case_letter?("A")
      refute UnicodeHelper.is_character_lower_case_letter?("Z")
      refute UnicodeHelper.is_character_lower_case_letter?("Ö")
      refute UnicodeHelper.is_character_lower_case_letter?("1")
      refute UnicodeHelper.is_character_lower_case_letter?("@")
      refute UnicodeHelper.is_character_lower_case_letter?(nil)
    end
  end

  describe "is_character_letter_or_digit?/1" do
    test "returns the correct data" do
      assert UnicodeHelper.is_character_letter_or_digit?("a")
      assert UnicodeHelper.is_character_letter_or_digit?("z")
      assert UnicodeHelper.is_character_letter_or_digit?("ö")
      assert UnicodeHelper.is_character_letter_or_digit?("ß")
      assert UnicodeHelper.is_character_letter_or_digit?("A")
      assert UnicodeHelper.is_character_letter_or_digit?("Z")
      assert UnicodeHelper.is_character_letter_or_digit?("Ö")
      assert UnicodeHelper.is_character_letter_or_digit?("1")

      refute UnicodeHelper.is_character_letter_or_digit?("@")
      refute UnicodeHelper.is_character_letter_or_digit?("]")
      refute UnicodeHelper.is_character_letter_or_digit?(nil)
    end
  end
end
