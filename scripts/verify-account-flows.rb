# frozen_string_literal: true
# Isolated, rollback-only checks. Emails are queued into memory, never delivered.
ActiveJob::Base.queue_adapter = :test
Rails.logger.level = Logger::WARN
User.transaction do
  password = "Verify-Aa1!#{SecureRandom.hex(12)}"
  email = "account-check-#{SecureRandom.hex(8)}@siet.ac.in"
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  client.get('/')
  headers = { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json',
              'HTTP_X_CSRF_TOKEN' => Nokogiri::HTML(client.response.body).at_css('meta[name="csrf-token"]')['content'] }
  post = lambda do |path, body|
    client.post("/api/v1/#{path}.json", params: body.to_json, headers:)
  end
  smtp = SmtpConfiguration.for_provider('greenlight')
  smtp.assign_attributes(enabled: false, port: 587, authentication: 'none', security: 'starttls')
  smtp.save!
  post.call('reset_password', { user: { email: } })
  raise 'Missing mail service was reported as success' unless client.response.status == 503
  smtp.update!(enabled: true, host: 'mail.invalid', domain: 'siet.ac.in', sender_email: 'test@siet.ac.in')
  post.call('users', { user: { name: 'Account verification', email:, password:, password_confirmation: password, language: 'en' } })
  raise "Signup failed: #{client.response.status}" unless client.response.status == 201
  user = User.find_by!(email:)
  raise 'Signup bypassed email verification' if user.verified?
  raise 'Verification email not queued' unless ActiveJob::Base.queue_adapter.enqueued_jobs.size == 1
  post.call('sessions', { session: { email:, password: } })
  raise 'Unverified sign-in accepted' unless JSON.parse(client.response.body)['errors'] == 'UnverifiedUser'

  token = user.generate_activation_token!
  post.call('verify_account/activate', { user: { token: } })
  raise 'Activation failed' unless client.response.status == 200 && user.reload.verified?
  post.call('verify_account/activate', { user: { token: } })
  raise 'Activation token was reusable' unless client.response.status == 403

  post.call('reset_password', { user: {} })
  raise 'Missing email did not return validation error' unless client.response.status == 400
  post.call('reset_password', { user: { email: } })
  raise 'Reset email not queued' unless client.response.status == 200 && ActiveJob::Base.queue_adapter.enqueued_jobs.size == 2
  reset = user.reload.generate_reset_token!
  post.call('reset_password/reset', { user: { token: reset, new_password: 'weak' } })
  raise 'Invalid password accepted' unless client.response.status == 400
  raise 'Invalid password consumed link' unless User.verify_reset_token(reset)
  replacement = "New-Aa1!#{SecureRandom.hex(12)}"
  old_session = user.reload.session_token
  post.call('reset_password/reset', { user: { token: reset, new_password: replacement } })
  raise 'Password reset failed' unless client.response.status == 200 && user.reload.authenticate(replacement)
  raise 'Old sessions were not revoked' if user.session_token == old_session
  post.call('reset_password/reset', { user: { token: reset, new_password: password } })
  raise 'Reset token was reusable' unless client.response.status == 403
  puts 'Signup verification, queued mail, token reuse, password validation and session revocation: OK'
  raise ActiveRecord::Rollback
end
