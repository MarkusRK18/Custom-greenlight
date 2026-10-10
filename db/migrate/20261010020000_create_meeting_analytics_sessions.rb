# frozen_string_literal: true

class CreateMeetingAnalyticsSessions < ActiveRecord::Migration[7.0]
  def up
    create_table :meeting_analytics_sessions do |t|
      t.references :room, type: :uuid, null: false, foreign_key: true
      t.string :internal_meeting_id, null: false
      t.jsonb :data, null: false
      t.timestamps
    end
    add_index :meeting_analytics_sessions, %i[room_id internal_meeting_id], unique: true, name: 'unique_room_analytics_session'
    execute <<~SQL
      INSERT INTO meeting_analytics_sessions (room_id, internal_meeting_id, data, created_at, updated_at)
      SELECT id, COALESCE(NULLIF(analytics_session_id, ''), 'legacy-' || id::text), analytics_data, NOW(), NOW()
      FROM rooms WHERE analytics_data IS NOT NULL;
    SQL
  end

  def down
    drop_table :meeting_analytics_sessions
  end
end
