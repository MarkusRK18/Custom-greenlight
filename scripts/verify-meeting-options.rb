# frozen_string_literal: true
# Run with: bundle exec rails runner scripts/verify-meeting-options.rb
# All fixture changes roll back; does not start a real BBB meeting.
Room.transaction do
  password = "Verify-Aa1!#{SecureRandom.hex(12)}"
  user = User.create!(name: 'Analytics verification', email: "analytics-#{SecureRandom.hex(8)}@siet.ac.in",
                      password: password, password_confirmation: password, verified: true, provider: 'greenlight', language: 'en')
  room = Room.create!(user: user, name: 'Duration verification', description: "Agenda\nDiscussion", meeting_type: 'instant', duration_minutes: 0)
  raise 'Meeting description not persisted' unless room.reload.description == "Agenda\nDiscussion"
  room.update!(scheduled_at: 3.days.ago, last_session: Time.current)
  raise 'Unlimited schedule closed' unless room.schedule_open?
  room.duration_minutes = 60
  raise 'Expired limited schedule open' if room.schedule_open?
  room.duration_minutes = 0
  starter = MeetingStarter.new(room: room, base_url: 'http://localhost:5050', current_user: user, provider: user.provider)
  options = starter.send(:computed_options, access_code: nil)
  raise 'Empty meetings do not expire' unless options[:meetingExpireWhenLastUserLeftInMinutes] == 1 &&
                                            options[:meetingExpireIfNoUserJoinedInMinutes] == 1
  captions = JSON.parse(options.fetch(:clientSettingsOverride)).dig('public', 'app', 'audioCaptions')
  raise 'Live English transcription not enabled' unless captions['enabled'] && captions['alwaysVisible'] &&
                                                         captions['provider'] == 'webspeech' &&
                                                         captions.dig('language', 'locale') == 'en-IN' &&
                                                         captions.dig('language', 'forceLocale') == true
  raise 'Live transcription excluded by server defaults' unless options[:disabledFeaturesExclude] == 'liveTranscription'
  raise 'Wrong BBB unlimited duration' unless options[:duration] == 0 && options[:keepEvents]
  raise 'Negative duration accepted' if room.tap { |r| r.duration_minutes = -1 }.valid?
  room.duration_minutes = 0
  room.save!

  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  auth_option = MeetingOption.find_by!(name: 'glRequireAuthentication')
  auth_setting = room.room_meeting_options.find_by!(meeting_option: auth_option)
  client.get("/api/v1/rooms/#{room.friendly_id}/public.json", headers: { 'HTTP_ACCEPT' => 'application/json' })
  raise 'Guest invitation requires sign-in' unless JSON.parse(client.response.body).dig('data', 'require_authentication') == 'false'
  auth_setting.update!(value: 'true')
  client.get("/api/v1/rooms/#{room.friendly_id}/public.json", headers: { 'HTTP_ACCEPT' => 'application/json' })
  raise 'Protected invitation did not require sign-in' unless JSON.parse(client.response.body).dig('data', 'require_authentication') == 'true'
  auth_setting.update!(value: 'false')
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
  raise 'Analytics not saved' unless room.meeting_analytics_sessions.first.data['duration'] == 90
  raise 'Private metadata saved' if room.meeting_analytics_sessions.first.data.key?('metadata')
  client.post('/analytics_callback', params: payload.to_json, headers: headers)
  raise 'Repeated callback created a duplicate session' unless room.meeting_analytics_sessions.count == 1
  payload[:internal_meeting_id] = "older-#{1.day.ago.to_i * 1000}"
  client.post('/analytics_callback', params: payload.to_json, headers: headers)
  raise 'Older session was lost' unless room.meeting_analytics_sessions.count == 2
  client.get("/api/v1/rooms/#{room.friendly_id}/analytics.json", headers: { 'HTTP_ACCEPT' => 'application/json' })
  raise 'Anonymous analytics accessible' unless client.response.status == 401
  json_headers = { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
  client.get('/')
  json_headers['HTTP_X_CSRF_TOKEN'] = Nokogiri::HTML(client.response.body).at_css('meta[name="csrf-token"]')['content']
  client.post('/api/v1/sessions.json', params: { session: { email: user.email, password: password } }.to_json, headers: json_headers)
  raise 'Fixture sign-in failed' unless client.response.status == 200
  client.patch("/api/v1/rooms/#{room.friendly_id}.json", params: { room: { description: 'Updated agenda' } }.to_json, headers: json_headers)
  raise 'Meeting description update failed' unless client.response.status == 200 && room.reload.description == 'Updated agenda'
  client.get("/api/v1/rooms/#{room.friendly_id}.json", headers: json_headers)
  raise 'Meeting description not exposed' unless JSON.parse(client.response.body)['data']['description'] == 'Updated agenda'
  client.get("/api/v1/rooms/#{room.friendly_id}/analytics.json", headers: json_headers)
  history = JSON.parse(client.response.body)['data']
  raise 'History list incorrect' unless client.response.status == 200 && history.length == 2 && history.first['participant_count'] == 1
  selected = history.first['id']
  client.get("/api/v1/rooms/#{room.friendly_id}/analytics/#{selected}.json", headers: json_headers)
  raise 'Saved dashboard inaccessible' unless client.response.status == 200 && JSON.parse(client.response.body)['data']['duration'] == 90
  other_room = Room.create!(user: user, name: 'Other session verification', meeting_type: 'instant', duration_minutes: 0)
  other_session = other_room.meeting_analytics_sessions.create!(internal_meeting_id: 'other-123', data: { duration: 1 })
  client.get("/api/v1/rooms/#{room.friendly_id}/analytics/#{other_session.id}.json", headers: json_headers)
  raise 'Session was accessible through the wrong meeting' unless client.response.status == 404

  user.update!(role: Role.find_by!(name: 'Administrator', provider: user.provider))
  record_option = MeetingOption.find_by!(name: 'record')
  room.room_meeting_options.find_or_create_by!(meeting_option: record_option).update!(value: 'true')
  captured_options = []
  BigBlueButtonApi.prepend(Module.new do
    define_method(:start_meeting) do |room:, options:, presentation_url:|
      captured_options << options
      { createTime: (Time.current.to_f * 1000).to_i }
    end
  end)
  starter.call
  raise 'Recordable meeting did not auto-start recording' unless captured_options.last['record'] == 'true' &&
                                                                captured_options.last['autoStartRecording'] == 'true' &&
                                                                captured_options.last['allowStartStopRecording'] == 'true'
  room.room_meeting_options.find_by!(meeting_option: record_option).update!(value: 'false')
  starter.call
  raise 'Disabled recording was auto-started' if captured_options.last.key?('autoStartRecording')

  record_id = "speaker-#{SecureRandom.hex(8)}"
  recording = Recording.create!(room:, record_id:, name: 'Speaker verification', visibility: 'Unpublished',
                                participants: 2, length: 1, recorded_at: Time.current)
  room.meeting_analytics_sessions.create!(internal_meeting_id: record_id,
                                          data: { attendees: [{ name: 'Speaker A', engagement: { talk_time: 42 } },
                                                               { name: 'Speaker B', engagement: { talk_time: 7 } }] })
  raise 'Speaker totals do not match this recording' unless recording.speaker_summary == [
    { name: 'Speaker A', talk_time_seconds: 42 }, { name: 'Speaker B', talk_time_seconds: 7 }
  ]
  puts 'Guest invitations, timing, callbacks, analytics access, automatic recording and speaker summaries: OK'
  raise ActiveRecord::Rollback
end
