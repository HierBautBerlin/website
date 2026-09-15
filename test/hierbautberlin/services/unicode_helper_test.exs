defmodule Hierbautberlin.Services.UnicodeHelperTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Services.UnicodeHelper

  describe "lower_case_letter?/1" do
    test "returns the correct data" do
      assert UnicodeHelper.lower_case_letter?("a")
      assert UnicodeHelper.lower_case_letter?("z")
      assert UnicodeHelper.lower_case_letter?("ö")
      assert UnicodeHelper.lower_case_letter?("ß")

      refute UnicodeHelper.lower_case_letter?("A")
      refute UnicodeHelper.lower_case_letter?("Z")
      refute UnicodeHelper.lower_case_letter?("Ö")
      refute UnicodeHelper.lower_case_letter?("1")
      refute UnicodeHelper.lower_case_letter?("@")
      refute UnicodeHelper.lower_case_letter?(nil)
    end
  end

  describe "letter_or_digit?/1" do
    test "returns the correct data" do
      assert UnicodeHelper.letter_or_digit?("a")
      assert UnicodeHelper.letter_or_digit?("z")
      assert UnicodeHelper.letter_or_digit?("ö")
      assert UnicodeHelper.letter_or_digit?("ß")
      assert UnicodeHelper.letter_or_digit?("A")
      assert UnicodeHelper.letter_or_digit?("Z")
      assert UnicodeHelper.letter_or_digit?("Ö")
      assert UnicodeHelper.letter_or_digit?("1")

      refute UnicodeHelper.letter_or_digit?("@")
      refute UnicodeHelper.letter_or_digit?("]")
      refute UnicodeHelper.letter_or_digit?(nil)
    end
  end
end
