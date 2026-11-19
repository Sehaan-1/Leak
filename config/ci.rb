# Run using bin/ci (local mirror of .github/workflows/ci.yml)

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Schema: structure.sql matches migrations", "bin/rails db:migrate && git diff --exit-code db/structure.sql"
  step "Tests: RSpec", "bin/rails db:test:prepare && bundle exec rspec"

  step "Web: install", "npm --prefix web ci"
  step "Web: API types match openapi.yaml", "npm --prefix web run api-types:check"
  step "Web: Biome", "npm --prefix web run lint"
  step "Web: TypeScript", "npm --prefix web run typecheck"
  step "Web: Vitest", "npm --prefix web test"
  step "Web: production build", "npm --prefix web run build"
end
