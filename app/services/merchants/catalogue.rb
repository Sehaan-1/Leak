module Merchants
  # The global merchant catalogue lives in config/merchants.yml (reviewed
  # like code) and is synced into merchants/merchant_aliases:
  #
  #   Merchants::Catalogue.sync!   # => { merchants: 55, aliases: 260 }
  #
  # Sync is idempotent. Catalogue aliases that left the file are deleted;
  # household-learnt aliases and merchants themselves are never deleted
  # (transactions may point at them).
  module Catalogue
    PATH = Rails.root.join("config/merchants.yml")

    Entry = Data.define(:slug, :name, :category, :aliases)

    module_function

    def entries(path = PATH)
      YAML.safe_load_file(path).map do |slug, attrs|
        names = Array(attrs["names"]).map { |name| [ "name", Text.key(name) ] }
        vpas = Array(attrs["vpas"]).map do |vpa|
          [ "vpa", Text.vpa(vpa) || raise(ArgumentError, "#{slug}: #{vpa.inspect} isn't a UPI ID") ]
        end
        Entry.new(slug, attrs.fetch("name"), attrs.fetch("category"), (names + vpas).uniq)
      end
    end

    # Problems a reviewer should fix before the catalogue can be synced.
    def problems(list = entries)
      owners = Hash.new { |hash, key| hash[key] = [] }
      list.each { |entry| entry.aliases.each { |pair| owners[pair] << entry.slug } }
      clashes = owners.select { |_, slugs| slugs.size > 1 }
        .map { |(kind, pattern), slugs| "#{kind} #{pattern} belongs to #{slugs.join(" and ")}" }
      blanks = list.select { |entry| entry.aliases.any? { |_, pattern| pattern.blank? } }
        .map { |entry| "#{entry.slug} has a name with no letters or digits" }
      unknown = list.reject { |entry| Merchant.categories.key?(entry.category) }
        .map { |entry| "#{entry.slug} has unknown category #{entry.category}" }
      clashes + blanks + unknown
    end

    def sync!(list = entries)
      problems(list).then { |found| raise ArgumentError, found.join("; ") if found.any? }

      ApplicationRecord.transaction do
        merchants = list.to_h do |entry|
          merchant = Merchant.find_or_initialize_by(slug: entry.slug)
          merchant.update!(name: entry.name, category: entry.category)
          [ entry.slug, merchant ]
        end
        wanted = list.flat_map { |entry| entry.aliases.map { |pair| [ pair, merchants[entry.slug].id ] } }.to_h
        # Delete first, so an alias can move from one merchant to another.
        stale = MerchantAlias.where(household_id: nil).reject { |row| wanted[[ row.kind, row.pattern ]] == row.merchant_id }
        MerchantAlias.where(id: stale.map(&:id)).delete_all
        present = MerchantAlias.where(household_id: nil).pluck(:kind, :pattern).to_set
        wanted.each do |(kind, pattern), merchant_id|
          MerchantAlias.create!(merchant_id: merchant_id, kind: kind, pattern: pattern) unless present.include?([ kind, pattern ])
        end
      end
      { merchants: list.size, aliases: list.sum { |entry| entry.aliases.size } }
    end
  end
end
