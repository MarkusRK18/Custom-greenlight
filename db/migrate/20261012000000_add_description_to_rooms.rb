# frozen_string_literal: true

class AddDescriptionToRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :rooms, :description, :text, default: '', null: false
  end
end
