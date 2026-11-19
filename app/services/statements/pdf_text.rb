require "open3"

module Statements
  # Extracts the text layer with poppler's `pdftotext -layout`, which keeps
  # column positions. Text-layer PDFs only: no OCR. A password, if given, is
  # passed straight to pdftotext and never stored.
  module PdfText
    MAX_BYTES = 10.megabytes

    module_function

    def extract(path, password: nil)
      raise ExtractionFailed, "The file is larger than 10 MB." if File.size(path) > MAX_BYTES
      raise ExtractionFailed, "That file isn't a PDF." unless File.binread(path, 5) == "%PDF-"

      args = [ "pdftotext", "-layout", "-enc", "UTF-8", "-eol", "unix" ]
      args += [ "-upw", password ] if password.present?
      stdout, stderr, status = run(args + [ path.to_s, "-" ])

      unless status.success?
        raise PasswordRequired, "This PDF is password-protected. Enter its password to import it." if stderr.match?(/password/i)
        raise ExtractionFailed, "Couldn't read this PDF."
      end

      text = stdout.dup.force_encoding(Encoding::UTF_8).scrub("")
      raise NoTextLayer, "This PDF has no text layer (scanned image?). Download the statement as a PDF from net banking instead." if text.strip.empty?

      text
    end

    def run(args)
      Open3.capture3(*args)
    rescue Errno::ENOENT
      raise ExtractionFailed, "pdftotext is not installed (apt install poppler-utils)."
    end
  end
end
