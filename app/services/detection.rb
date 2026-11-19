# Recurring-charge detection: see Detection::Engine and config/detection.yml.
module Detection
  CONFIG = Rails.root.join("config/detection.yml")

  # A statement line as detection sees it. amount_paise is signed: debits
  # are negative. merchant is a slug, category its catalogue category.
  Txn = Data.define(:id, :merchant, :category, :on, :amount_paise)

  Cadence = Data.define(:name, :period, :tolerance, :min_charges) do
    # Days from one charge to the k-th next.
    def offset(k = 1) = (period * k).round
  end

  # Monthly cost factors, exact so a monthly ₹649 stays ₹649.
  MONTHLY_FACTOR = { "weekly" => Rational(52, 12), "monthly" => 1, "quarterly" => Rational(1, 3),
                     "half_yearly" => Rational(1, 6), "annual" => Rational(1, 12) }.freeze

  module_function

  def config
    @config ||= YAML.safe_load_file(CONFIG).freeze
  end

  def cadences(settings = config)
    settings.fetch("cadences").to_h do |name, attrs|
      [ name, Cadence.new(name, attrs.fetch("period").to_f, attrs.fetch("tolerance"), attrs.fetch("min_charges")) ]
    end
  end

  def monthly_cost(amount_paise, cadence) = (amount_paise * MONTHLY_FACTOR.fetch(cadence)).round
end
