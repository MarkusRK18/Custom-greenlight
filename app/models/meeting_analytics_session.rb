# frozen_string_literal: true

class MeetingAnalyticsSession < ApplicationRecord
  belongs_to :room
  validates :internal_meeting_id, presence: true, uniqueness: { scope: :room_id }
  validates :data, presence: true

  def summary
    started = data['start']
    timestamp = internal_meeting_id.split('-').last.to_i
    started ||= Time.at(timestamp / 1000.0).iso8601 if timestamp.positive?
    {
      id: id,
      started_at: started,
      ended_at: data['finish'],
      duration_seconds: data['duration'],
      participant_count: Array(data['attendees']).length,
      saved_at: created_at
    }
  end
end
