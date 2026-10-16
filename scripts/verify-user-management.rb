# frozen_string_literal: true
# Rollback-only API checks; no existing accounts or BBB recordings are changed.
previous_forgery = ActionController::Base.allow_forgery_protection
ActionController::Base.allow_forgery_protection = false
deleted_recordings = []
fixture_cleanup = Module.new do
  define_method(:delete_recordings) do |record_ids:|
    raise 'Verification attempted to delete a non-fixture BBB recording' unless record_ids.start_with?('user-management-check-')

    deleted_recordings << record_ids
    { returncode: 'SUCCESS' }
  end
end
BigBlueButtonApi.prepend(fixture_cleanup)
begin
  User.transaction do
    password = "Check-User1!#{SecureRandom.hex(12)}"
    attributes = { password:, verified: true, provider: 'greenlight', language: 'en' }
    admin = User.create!(**attributes, name: 'Management check', email: "manage-#{SecureRandom.hex(8)}@siet.ac.in")
    target = User.create!(**attributes, name: 'Legacy check', email: "legacy-#{SecureRandom.hex(8)}@siet.ac.in")
    target_client = ActionDispatch::Integration::Session.new(Rails.application)
    target_client.host! 'localhost'
    target_client.post('/api/v1/sessions.json', params: { session: { email: target.email, password: } }, as: :json)
    raise 'Target login failed' unless target_client.response.status == 200
    room = Room.create!(user: target, name: 'Deletion check', meeting_type: 'instant')
    recording = room.recordings.create!(name: 'Deletion fixture', record_id: "user-management-check-#{SecureRandom.hex(8)}",
                                        visibility: 'Published', length: 1, participants: 1)
    room.meeting_analytics_sessions.create!(internal_meeting_id: "check-#{SecureRandom.hex(8)}", data: { 'duration' => 1 })
    # Emulate an account imported before institutional signup was enforced.
    target.update_columns(email: "legacy-#{SecureRandom.hex(8)}@example.com")
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.host! 'localhost'
    client.post('/api/v1/sessions.json', params: { session: { email: admin.email, password: } }, as: :json)
    raise 'Admin login failed' unless client.response.status == 200
    client.patch("/api/v1/admin/users/#{target.id}.json", params: { user: { status: 'banned' } }, as: :json)
    raise "Legacy ban failed: HTTP #{client.response.status}" unless client.response.status == 200 && target.reload.banned?
    target_client.get("/api/v1/users/#{target.id}.json", as: :json)
    raise 'Banned session remained authenticated' unless target_client.response.status == 401
    client.patch("/api/v1/admin/users/#{target.id}.json", params: { user: { status: 'active' } }, as: :json)
    raise 'Legacy unban failed' unless client.response.status == 200 && target.reload.active?
    target.email = 'still-outside@example.com'
    raise 'New external email accepted' if target.valid?
    target.reload
    client.delete("/api/v1/users/#{target.id}.json", as: :json)
    raise "User deletion failed: HTTP #{client.response.status}" unless client.response.status == 200 && !User.exists?(target.id)
    raise 'Dependent room not deleted' if Room.exists?(room.id)
    raise 'Recording cleanup not called' unless deleted_recordings.include?(recording.record_id) && !Recording.exists?(recording.id)
    puts 'Admin legacy ban/unban, signup email guard and user/room/analytics deletion: OK'
    raise ActiveRecord::Rollback
  end
ensure
  ActionController::Base.allow_forgery_protection = previous_forgery
end
