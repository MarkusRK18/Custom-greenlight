# frozen_string_literal: true
# Run with: bundle exec rails runner scripts/verify-meeting-options.rb
# All fixture changes roll back; does not start a real BBB meeting.
user = User.find_by!(email: 'student_name@siet.ac.in')
Room.transaction do
  room = Room.create!(user: user, name: 'Duration verification', meeting_type: 'instant', duration_minutes: 0)
  room.update!(scheduled_at: 3.days.ago, last_session: Time.current)
  raise 'Unlimited schedule closed' unless room.schedule_open?
  room.duration_minutes = 60
  raise 'Expired limited schedule open' if room.schedule_open?
  room.duration_minutes = 0
  starter = MeetingStarter.new(room: room, base_url: 'http://localhost:5050', current_user: user, provider: user.provider)
  options = starter.send(:computed_options, access_code: nil)
  raise 'Wrong BBB unlimited duration' unless options[:duration] == 0 && options[:keepEvents]
  raise 'Negative duration accepted' if room.tap { |r| r.duration_minutes = -1 }.valid?
  room.duration_minutes = 0
  room.save!

  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  payload = {
    meeting_id: room.meeting_id,
    internal_meeting_id: "test-#{room.last_session.to_time.to_i * 1000}",
    data: { duration: 90, attendees: [{ name: 'Test participant', duration: 60 }], metadata: { private_url: 'filtered' } }
  }
  headers = { 'CONTENT_TYPE' => 'application/json' }
  client.post('/analytics_callback', params: payload.to_json, headers: headers)
  raise 'Unauthenticated callback accepted' unless client.response.status == 401
  token = JWT.encode({ exp: 1.hour.from_now.to_i }, ENV.fetch('BIGBLUEBUTTON_SECRET'), 'HS512')
  headers['HTTP_AUTHORIZATION'] = "Bearer #{token}"
  client.post('/analytics_callback', params: payload.to_json, headers: headers)
  raise "Callback failed: #{client.response.status}" unless client.response.status == 200
  raise 'Analytics not saved' unless room.reload.analytics_data['duration'] == 90
  raise 'Private metadata saved' if room.analytics_data.key?('metadata')
  client.get("/api/v1/rooms/#{room.friendly_id}/analytics.json", headers: { 'HTTP_ACCEPT' => 'application/json' })
  raise 'Anonymous analytics accessible' unless client.response.status == 401
  puts 'Unlimited/limited timing, BBB options, callback authentication, analytics storage and access: OK'
  raise ActiveRecord::Rollback
end
