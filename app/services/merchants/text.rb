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

    # pg_trgm's similarity(), for checks done in Ruby (the LLM validator):
    #   Text.similarity("HDFCSTANDARDLIFE", "HDFCLIFE") # => 0.368
    def similarity(left, right)
      a = trigrams(left)
      b = trigrams(right)
      return 0.0 if a.empty? || b.empty?

      (a & b).size.fdiv((a | b).size)
    end

    def trigrams(text)
      text.to_s.downcase.split(/[^a-z0-9]+/).reject(&:empty?).each_with_object(Set.new) do |word, set|
        "  #{word} ".chars.each_cons(3) { |chars| set << chars.join }
      end
    end
  end
end
