# frozen_string_literal: true

require "bundler/setup"
require "logger"
require "webmock/rspec"

WebMock.disable_net_connect!

module GraphStubs
  TOKEN_URL = %r{\Ahttps://login\.microsoftonline\.com/[^/]+/oauth2/v2\.0/token\z}
  SEND_MAIL_URL = %r{\Ahttps://graph\.microsoft\.com/v1\.0/users/[^/]+/sendMail\z}

  def stub_token(token: "token-1", expires_in: 3600)
    stub_request(:post, TOKEN_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { access_token: token, expires_in: expires_in, token_type: "Bearer" }.to_json
    )
  end

  def stub_send_mail(status: 202, body: "", headers: {})
    stub_request(:post, SEND_MAIL_URL).to_return(status: status, body: body, headers: headers)
  end

  def graph_error(code)
    { error: { code: code, message: "test" } }.to_json
  end

  def sent_json(request)
    JSON.parse(request.body)
  end

  def sent_mime(request)
    request.body.unpack1("m0")
  end
end

RSpec.configure do |config|
  config.include GraphStubs
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
