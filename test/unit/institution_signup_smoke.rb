# Run with bundle exec rails runner test/unit/institution_signup_smoke.rb
Rails.logger.level = Logger::FATAL
ActionController::Base.allow_forgery_protection = false
# A configured SMTP server must not trigger an activation email.
ENV['SMTP_SERVER'] = 'smtp.invalid'
def UserMailer.with(*)
  raise 'Signup attempted to send a verification email'
end

def check(condition, message)
  raise message unless condition
  puts "PASS: #{message}"
end

ActiveRecord::Base.transaction do
  setting = Setting.find_by!(name: 'RegistrationMethod')
  SiteSetting.find_by!(setting: setting, provider: 'greenlight').update!(value: 'open')
  email = "signup-test-#{SecureRandom.hex(4)}@siet.ac.in"
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  client.post '/api/v1/users.json', params: { user: { name: 'Signup Test', email: email.upcase, password: 'Testing1!Local', role_id: Role.find_by!(name: 'User', provider: 'greenlight').id } }, as: :json
  check(client.response.status == 201, 'SIET signup succeeds without verification mail')
  user = User.find_by!(email: email)
  check(user.verified? && user.verification_digest.nil?, 'Account is activated without an activation token')
  check(user.role.name == 'Administrator' && InstitutionPolicy.host?(user), 'SIET signup creates an administrator')
  login = ActionDispatch::Integration::Session.new(Rails.application)
  login.host! 'localhost'
  login.post '/api/v1/sessions.json', params: { session: { email: email, password: 'Testing1!Local' } }, as: :json
  check(login.response.status == 200, 'New account can immediately sign in')
  %w[srishakthi.ac.in siet.ac.in.evil.test sub.siet.ac.in].each do |domain|
    outsider = ActionDispatch::Integration::Session.new(Rails.application)
    outsider.host! 'localhost'
    outsider.post '/api/v1/users.json', params: { user: { name: 'Outside Test', email: "signup-test@#{domain}", password: 'Testing1!Local' } }, as: :json
    check(outsider.response.status == 400, "Signup rejects #{domain}")
  end
  raise ActiveRecord::Rollback
end
