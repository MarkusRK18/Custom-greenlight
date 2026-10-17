# frozen_string_literal: true
# Rollback-only checks; SMTP delivery and connection testing are simulated.
Rails.logger.level = Logger::WARN
ActionController::Base.allow_forgery_protection = false
sent = []
Mail::SMTP.prepend(Module.new do
  define_method(:deliver!) do |message|
    sent << { to: message.to, from: message.from, settings: settings.dup }
  end
end)
connections = []
SmtpConfiguration.prepend(Module.new do
  define_method(:test_connection!) do
    raise 'Invalid SMTP settings' unless configured?

    connections << provider
  end
end)

User.transaction do
  password = "Check-Aa1!#{SecureRandom.hex(12)}"
  admin = User.create!(name: 'SMTP administrator', email: "smtp-check-#{SecureRandom.hex(8)}@siet.ac.in",
                       password:, verified: true, provider: 'greenlight', language: 'en')
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  endpoint = '/api/v1/admin/smtp_configuration'
  client.get("#{endpoint}.json", as: :json)
  raise 'Anonymous SMTP access accepted' unless client.response.status == 401
  client.post('/api/v1/sessions.json', params: { session: { email: admin.email, password: } }, as: :json)
  raise 'Admin sign-in failed' unless client.response.status == 200

  values = { enabled: true, host: 'smtp.example.invalid', port: 587, domain: 'siet.ac.in',
             username: 'smtp-user', password: SecureRandom.hex(20), authentication: 'login', security: 'starttls',
             sender_email: 'noreply@siet.ac.in', sender_name: 'SIETConnect' }
  client.patch("#{endpoint}.json", params: { smtp_configuration: values }, as: :json)
  raise "SMTP save failed: #{client.response.status}" unless client.response.status == 200
  config = SmtpConfiguration.find_by!(provider: 'greenlight')
  raise 'Password not encrypted' if config.encrypted_password.include?(values[:password])
  raise 'Password round-trip failed' unless config.password == values[:password]
  unreadable = config.dup
  unreadable.encrypted_password = 'invalid-ciphertext'
  raise 'Unreadable password could not be replaced through the GUI' if unreadable.password.present? || unreadable.public_settings['password_configured']
  raise 'Password leaked in save response' if client.response.body.include?(values[:password]) || client.response.body.include?('encrypted_password')
  encrypted = config.encrypted_password
  client.patch("#{endpoint}.json", params: { smtp_configuration: { password: '', sender_name: 'College' } }, as: :json)
  raise 'Blank password overwrote stored credential' unless client.response.status == 200 && config.reload.encrypted_password == encrypted
  client.get("#{endpoint}.json", as: :json)
  public_config = JSON.parse(client.response.body).fetch('data')
  raise 'Password leaked in read response' if public_config.key?('password') || public_config.key?('encrypted_password')
  raise 'Read response missing status' unless public_config['configured'] && public_config['password_configured']
  client.get('/api/v1/env.json', as: :json)
  raise 'Public SMTP status missing' unless JSON.parse(client.response.body).dig('data', 'SMTP_ENABLED') == true

  client.post("#{endpoint}/test_connection.json", as: :json)
  raise 'Connection action failed' unless client.response.status == 200 && connections == ['greenlight']
  client.post("#{endpoint}/test_email.json", params: { recipient: 'ignored@example.invalid' }, as: :json)
  raise 'Test email failed' unless client.response.status == 200 && sent.size == 1
  raise 'Test email recipient was not restricted to current admin' unless sent.first[:to] == [admin.email]
  raise 'Saved sender not applied' unless sent.first[:from] == ['noreply@siet.ac.in']
  raise 'Saved credentials not applied' unless sent.first[:settings][:password] == values[:password]
  raise 'TLS verification was disabled' unless sent.first[:settings][:openssl_verify_mode] == OpenSSL::SSL::VERIFY_PEER

  other = SmtpConfiguration.create!(provider: "smtp-other-#{SecureRandom.hex(5)}", **values.except(:password).merge(password: 'Other-secret'))
  raise 'Provider isolation failed' unless SmtpConfiguration.for_provider(other.provider).password == 'Other-secret' && config.password == values[:password]
  client.patch("#{endpoint}.json", params: { smtp_configuration: { security: 'off' } }, as: :json)
  raise 'Unencrypted SMTP allowed' unless client.response.status == 422 && config.reload.security == 'starttls'
  client.patch("#{endpoint}.json", params: { smtp_configuration: { enabled: false } }, as: :json)
  raise 'Disable failed' unless client.response.status == 200 && !SmtpConfiguration.configured?(provider: 'greenlight')
  client.post("#{endpoint}/test_email.json", as: :json)
  raise 'Disabled SMTP sent email' unless client.response.status == 422 && sent.size == 1

  admin.update!(role: Role.find_by!(name: 'User', provider: 'greenlight'))
  client.get("#{endpoint}.json", as: :json)
  raise 'Non-admin could read SMTP configuration' unless client.response.status == 403
  client.patch("#{endpoint}.json", params: { smtp_configuration: values }, as: :json)
  raise 'Non-admin could change SMTP configuration' unless client.response.status == 403
  client.post("#{endpoint}/test_email.json", as: :json)
  raise 'Non-admin could send test email' unless client.response.status == 403 && sent.size == 1
  puts 'SMTP permissions, encryption, password preservation, tenant isolation, TLS and per-message delivery: OK'
  raise ActiveRecord::Rollback
end
