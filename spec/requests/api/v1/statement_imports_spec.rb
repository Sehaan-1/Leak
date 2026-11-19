require "rails_helper"

RSpec.describe "API v1 statement imports" do
  let(:user) { create_user }

  def upload(path = StatementFixtures::SAMPLE_PDF, content_type: "application/pdf", **params)
    post api_v1_statement_imports_path, params: { file: Rack::Test::UploadedFile.new(path, content_type), **params }
  end

  it "requires a session" do
    get api_v1_statement_imports_path, as: :json
    assert_response_schema_confirm(401)
  end

  it "imports the sample PDF, then returns the same import on re-upload" do
    require_pdftotext!
    sign_in(user)

    upload
    assert_response_schema_confirm(201)
    expect(json).to include("status" => "imported", "rows_count" => 7, "new_rows_count" => 7,
      "closing_balance_paise" => 24_850_75, "error" => nil, "filename" => "sample_statement.pdf")
    expect(json["bank_account"]).to include("name" => "SBI ••9475")
    first_id = json["id"]

    upload
    assert_response_schema_confirm(200)
    expect(json["id"]).to eq(first_id)

    get api_v1_statement_imports_path, as: :json
    assert_response_schema_confirm(200)
    expect(json["statement_imports"].map { |i| i["id"] }).to eq([ first_id ])
  end

  it "returns 422 with the reason for a file it can't import" do
    sign_in(user)
    Tempfile.create([ "notes", ".pdf" ]) do |file|
      file.write("not a pdf")
      file.flush
      upload(file.path)
    end

    assert_response_schema_confirm(422)
    expect(json).to include("status" => "rejected")
    expect(json.dig("error", "message")).to match(/isn't a PDF/)
  end

  it "returns 400 without a file" do
    sign_in(user)
    post api_v1_statement_imports_path, params: {}
    assert_response_schema_confirm(400)
  end

  it "doesn't show other households' imports" do
    Statements::Importer.import_text(household: create_household(name: "Neighbours"), text: sample_text, filename: "x.pdf")
    sign_in(user)
    get api_v1_statement_imports_path, as: :json
    expect(json["statement_imports"]).to eq([])
  end
end
