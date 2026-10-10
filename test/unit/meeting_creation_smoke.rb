# Run inside the local portal with: bundle exec rails runner test/unit/meeting_creation_smoke.rb
Rails.logger.level = Logger::FATAL
ActionController::Base.allow_forgery_protection = false

def check(condition, message)
  raise message unless condition
  puts "PASS: #{message}"
end

ActiveRecord::Base.transaction do
  admin = User.find_by!(email: ENV.fetch('LOCAL_ADMIN_EMAIL', 'student_name@siet.ac.in'))
  password = File.read(Rails.root.join('storage/local-admin-credentials.txt')).lines.find { |line| line.start_with?('Password: ') }.delete_prefix('Password: ').strip
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  client.post '/api/v1/sessions.json', params: { session: { email: admin.email, password: password } }, as: :json
  check(client.response.status == 200, 'Host sign-in')
  base = { user_id: admin.id, duration_minutes: 60 }
  client.post '/api/v1/rooms.json', params: { room: base.merge(name: 'Instant test', meeting_type: 'instant', scheduled_at: 1.day.from_now.iso8601) }, as: :json
  check(client.response.status == 201, 'Instant creation succeeds')
  instant = admin.rooms.find_by!(name: 'Instant test')
  check(instant.schedule_open? && (instant.scheduled_at - Time.current).abs < 10, 'Instant start uses server time and is immediately available')
  options = MeetingStarter.new(room: instant, base_url: 'http://localhost:5050', current_user: admin, provider: admin.provider).send(:computed_options, access_code: '')
  check(options[:bannerText].empty? && options[:welcome] == 'Welcome to SIETConnect', 'Meeting has SIETConnect welcome and no banner')
  join = BigBlueButtonApi.new(provider: admin.provider).join_meeting(room: instant, role: 'Moderator', name: admin.name)
  query = URI.decode_www_form(URI.parse(join).query).to_h
  check(query['userdata-bbb_hide_presentation_on_join'] == 'true' && query['userdata-bbb_show_session_details_on_join'] == 'false', 'Presentation and session details start hidden')
  start = 1.day.from_now.change(usec: 0)
  client.post '/api/v1/rooms.json', params: { room: base.merge(name: 'Scheduled test', meeting_type: 'scheduled', scheduled_at: start.iso8601) }, as: :json
  check(client.response.status == 201, 'Scheduled creation succeeds')
  scheduled = admin.rooms.find_by!(name: 'Scheduled test')
  check(scheduled.scheduled_at == start && !scheduled.schedule_open?, 'Scheduled meeting retains its future time')
  client.post '/api/v1/rooms.json', params: { room: base.merge(name: 'Missing time', meeting_type: 'scheduled') }, as: :json
  check(client.response.status == 400, 'Scheduled meetings require a date')
  client.post '/api/v1/rooms.json', params: { room: base.merge(name: 'Invalid type', meeting_type: 'other', scheduled_at: start.iso8601) }, as: :json
  check(client.response.status == 400, 'Unknown meeting types are rejected')
  student = User.create!(name: 'Meeting Test Student', email: "meeting-test-#{SecureRandom.hex(4)}@siet.ac.in", password: 'Testing1!Local', role: Role.find_by!(name: 'User', provider: admin.provider), provider: admin.provider, verified: true, language: 'en')
  student_client = ActionDispatch::Integration::Session.new(Rails.application)
  student_client.host! 'localhost'
  student_client.post '/api/v1/sessions.json', params: { session: { email: student.email, password: 'Testing1!Local' } }, as: :json
  check(student_client.response.status == 200, 'Student sign-in')
  %w[instant scheduled].each do |type|
    student_client.post '/api/v1/rooms.json', params: { room: base.merge(user_id: student.id, name: 'Forbidden meeting', meeting_type: type, scheduled_at: start.iso8601) }, as: :json
    check(student_client.response.status == 201, "Institutional accounts can create #{type} meetings")
  end
  raise ActiveRecord::Rollback
end
