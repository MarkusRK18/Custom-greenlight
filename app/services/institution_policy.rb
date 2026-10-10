# frozen_string_literal: true

class InstitutionPolicy
  DOMAIN = 'siet.ac.in'
  HOST_ROLES = %w[Administrator Faculty Staff SuperAdmin].freeze

  def self.member?(user)
    user.present? && user.active? && user.verified? && user.email.to_s.split('@').last&.downcase == DOMAIN
  end

  def self.host?(user)
    member?(user) && HOST_ROLES.include?(user.role.name)
  end
end
