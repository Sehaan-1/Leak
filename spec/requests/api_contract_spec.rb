require "rails_helper"

# Every /api route must be documented in openapi/openapi.yaml, and every
# documented operation must exist, so the contract can't silently drift.
RSpec.describe "OpenAPI contract coverage" do
  it "documents exactly the routes that exist under /api" do
    spec = YAML.load_file(Rails.root.join("openapi/openapi.yaml"))
    documented = spec.fetch("paths").flat_map { |path, ops|
      (ops.keys & %w[ get post put patch delete ]).map { |verb| "#{verb.upcase} #{path}" }
    }.sort

    routed = Rails.application.routes.routes.filter_map { |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      next unless path.start_with?("/api/")
      "#{route.verb} #{path.gsub(/:(\w+)/, '{\1}')}"
    }.uniq.sort

    expect(routed).to eq(documented)
  end
end
