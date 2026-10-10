# frozen_string_literal: true

class AddScheduleToRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :rooms, :scheduled_at, :datetime
    add_column :rooms, :duration_minutes, :integer, default: 60, null: false
    add_column :rooms, :participant_emails, :text, default: '', null: false
  end
end
