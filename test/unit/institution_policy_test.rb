# frozen_string_literal: true

require 'ostruct'
require_relative '../../app/services/institution_policy'

class InstitutionPolicyTest
  def assert(value)
    raise 'Expected a truthy value' unless value
  end

  def refute(value)
    raise 'Expected a falsey value' if value
  end

  UserStub = Struct.new(:email, :role, :verified, :active) do
    def present? = true
    def verified? = verified
    def active? = active
  end

  def user(email: 'student@siet.ac.in', role: 'User', verified: true, active: true)
    UserStub.new(email, OpenStruct.new(name: role), verified, active)
  end

  def test_verified_student_can_join_but_cannot_host
    assert InstitutionPolicy.member?(user)
    refute InstitutionPolicy.host?(user)
  end

  def test_only_explicit_staff_roles_can_host
    %w[Administrator Faculty Staff].each { |role| assert InstitutionPolicy.host?(user(role: role)) }
    %w[User Guest Student].each { |role| refute InstitutionPolicy.host?(user(role: role)) }
  end

  def test_domain_suffix_attack_and_subdomains_are_rejected
    %w[user@siet.ac.in.evil.test user@evil-siet.ac.in user@sub.siet.ac.in].each do |email|
      refute InstitutionPolicy.member?(user(email: email))
    end
  end

  def test_unverified_and_inactive_staff_cannot_host
    refute InstitutionPolicy.host?(user(role: 'Faculty', verified: false))
    refute InstitutionPolicy.host?(user(role: 'Faculty', active: false))
    assert InstitutionPolicy.member?(user(email: 'USER@SIET.AC.IN'))
  end
end

check = InstitutionPolicyTest.new
InstitutionPolicyTest.instance_methods.grep(/^test_/).each { |test| check.public_send(test) }
puts '4 institution policy checks passed'
