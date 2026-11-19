module StatementFixtures
  SAMPLE_PDF = Rails.root.join("spec/fixtures/synthetic/sbi/sample_statement.pdf")
  SAMPLE_TEXT = Rails.root.join("spec/fixtures/synthetic/sbi/sample_statement.layout.txt")

  def sample_text
    SAMPLE_TEXT.read
  end

  def pdftotext_available?
    system("pdftotext", "-v", out: File::NULL, err: File::NULL)
  end

  # Locally, PDF specs skip without poppler; CI sets REQUIRE_PDFTOTEXT=1 so
  # they can never silently skip there.
  def require_pdftotext!
    return if pdftotext_available?
    raise "pdftotext missing but REQUIRE_PDFTOTEXT is set" if ENV["REQUIRE_PDFTOTEXT"]

    skip "pdftotext (poppler-utils) is not installed"
  end
end

RSpec.configure { |config| config.include StatementFixtures }
