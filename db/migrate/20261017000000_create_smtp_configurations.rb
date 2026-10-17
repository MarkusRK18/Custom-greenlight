# frozen_string_literal: true

class CreateSmtpConfigurations < ActiveRecord::Migration[7.0]
  def change
    create_table :smtp_configurations do |t|
      t.string :provider, null: false
      t.boolean :enabled, null: false, default: true
      t.string :host
      t.integer :port, default: 587
      t.string :domain
      t.string :username
      t.text :encrypted_password
      t.string :authentication, default: 'login'
      t.string :security, default: 'starttls'
      t.string :sender_email
      t.string :sender_name, default: 'SIETConnect'
      t.timestamps
    end
    add_index :smtp_configurations, :provider, unique: true
  end
end
