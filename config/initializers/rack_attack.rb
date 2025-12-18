class Rack::Attack
  throttle("logins/ip", limit: 20, period: 60.seconds) do |req|
    req.ip if req.path == "/login" && req.post?
  end
end

Rails.application.config.middleware.use Rack::Attack
