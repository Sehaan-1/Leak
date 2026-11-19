module Merchants
  # Normalisation shared by the catalogue, the narration parser and the
  # resolver. Statement narrations wrap at a fixed width and the importer
  # joins the pieces with a space, so a space can land anywhere, even inside
  # a UPI ID ("metromart@hdfcban k"). Everything is compared space-free.
  module Text
    VPA = /\A[a-z0-9._-]+@[a-z0-9]+\z/

    module_function

    # "Netflix Entertainment Services" => "NETFLIXENTERTAINMENTSERVICES"
    def key(text)
      text.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    end

    # " NetflixUPI@ICICI " => "netflixupi@icici"; nil unless it looks like a UPI ID.
    def vpa(text)
      candidate = text.to_s.downcase.gsub(/\s+/, "")
      candidate if candidate.match?(VPA)
    end

    def compact(text)
      text.to_s.gsub(/\s+/, "")
    end
  end
end
