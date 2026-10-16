# frozen_string_literal: true
# Rollback-only invitation checks. BBB calls are simulated; no real meeting starts.
starts = []
BigBlueButtonApi.prepend(Module.new do
  define_method(:meeting_running?) { |room:| false }
  define_method(:start_meeting) do |room:, options:, presentation_url:|
    starts << room.id
    { createTime: (Time.current.to_f * 1000).to_i }
  end
  define_method(:join_meeting) { |room:, role:, name: nil, avatar_url: nil| "https://meeting.invalid/join/#{role}" }
end)

Room.transaction do
  password = "Verify-Aa1!#{SecureRandom.hex(12)}"
  user = User.create!(name: 'Invitation verification', email: "invite-#{SecureRandom.hex(8)}@siet.ac.in",
                      password:, password_confirmation: password, verified: true, provider: 'greenlight', language: 'en')
  user.update!(role: Role.find_by!(name: 'Administrator', provider: user.provider))
  room = Room.create!(user:, name: 'Invitation verification', meeting_type: 'instant', scheduled_at: 1.minute.ago, duration_minutes: 0)
  set_option = lambda do |name, value|
    room.room_meeting_options.find_by!(meeting_option: MeetingOption.find_by!(name:)).update!(value:)
  end
  set_option.call('glAnyoneCanStart', 'true')
  set_option.call('glRequireAuthentication', 'false')
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.host! 'localhost'
  client.get('/')
  headers = { 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json',
              'HTTP_X_CSRF_TOKEN' => Nokogiri::HTML(client.response.body).at_css('meta[name="csrf-token"]')['content'] }
  join = lambda do
    client.post("/api/v1/meetings/#{room.friendly_id}/status.json", params: { name: 'Link invitee' }.to_json, headers:)
  end
  join.call
  raise 'Invitee could not start and join as Viewer' unless client.response.status == 200 && starts == [room.id] &&
                                                         JSON.parse(client.response.body).dig('data', 'joinUrl') == 'https://meeting.invalid/join/Viewer'
  set_option.call('glAnyoneCanStart', 'false')
  join.call
  raise 'Disabled link start was ignored' unless client.response.status == 200 && starts.size == 1 &&
                                                JSON.parse(client.response.body).dig('data', 'status') == false
  set_option.call('glAnyoneCanStart', 'true')
  set_option.call('glRequireAuthentication', 'true')
  join.call
  raise 'Sign-in requirement was bypassed' unless client.response.status == 401 && starts.size == 1
  set_option.call('glRequireAuthentication', 'false')
  set_option.call('glViewerAccessCode', 'required-code')
  join.call
  raise 'Viewer code was bypassed' unless client.response.status == 403 && starts.size == 1
  set_option.call('glViewerAccessCode', '')
  room.update!(scheduled_at: 1.hour.from_now)
  join.call
  raise 'Schedule was bypassed' unless client.response.status == 403 && starts.size == 1
  puts 'Invitation start, Viewer role, sign-in, access code and schedule checks: OK'
  raise ActiveRecord::Rollback
end
