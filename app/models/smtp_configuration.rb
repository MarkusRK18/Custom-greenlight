# frozen_string_literal: true

require 'net/smtp'

class SmtpConfiguration < ApplicationRecord
  PUBLIC_FIELDS = %w[enabled host port domain username authentication security sender_email sender_name].freeze
  validates :provider, presence: true, uniqueness: true
  validates :host, :domain, :sender_email, presence: true, if: :enabled?
  validates :host, format: { with: /\A[a-zA-Z0-9._:-]+\z/ }, allow_blank: true
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }
  validates :authentication, inclusion: { in: %w[login plain none] }
  validates :security, inclusion: { in: %w[starttls tls] }
  validates :sender_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :username, :password, presence: true, if: -> { enabled? && authentication != 'none' }
  validates :domain, :sender_email, :sender_name, :username, format: { without: /[\r\n]/ }, allow_nil: true

  def self.for_provider(provider)
    find_by(provider:) || new(
      provider:, enabled: ENV['SMTP_SERVER'].present?, host: ENV['SMTP_SERVER'], port: ENV.fetch('SMTP_PORT', 587),
      domain: ENV['SMTP_DOMAIN'], username: ENV['SMTP_USERNAME'], password: ENV['SMTP_PASSWORD'],
      authentication: ENV.fetch('SMTP_AUTH', 'none').presence || 'none',
      security: ActiveModel::Type::Boolean.new.cast(ENV['SMTP_TLS']) ? 'tls' : 'starttls',
      sender_email: ENV['SMTP_SENDER_EMAIL'], sender_name: ENV.fetch('SMTP_SENDER_NAME', 'SIETConnect')
    )
  end

  def self.configured?(provider:)
    for_provider(provider).configured?
  end

  def password
    return nil if encrypted_password.blank?

    encryptor.decrypt_and_verify(encrypted_password, purpose: "smtp:#{provider}")
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    # Keep the form usable so an administrator can replace an unreadable secret.
    nil
  end

  def password=(value)
    self.encrypted_password = value.present? ? encryptor.encrypt_and_sign(value, purpose: "smtp:#{provider}") : nil
  end

  def configured?
    enabled? && valid?
  end

  def public_settings
    attributes.slice(*PUBLIC_FIELDS).merge('password_configured' => password.present?,
                                          'configured' => configured?, 'source' => persisted? ? 'administration' : 'environment')
  end

  def smtp_settings
    { address: host, port:, domain:, user_name: authentication == 'none' ? nil : username,
      password: authentication == 'none' ? nil : password, authentication: authentication == 'none' ? nil : authentication,
      enable_starttls_auto: security == 'starttls', enable_starttls: security == 'starttls', tls: security == 'tls',
      openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER, open_timeout: 5, read_timeout: 10 }
  end

  def test_connection!
    raise ArgumentError, 'SMTP is not configured' unless configured?

    smtp = Net::SMTP.new(host, port)
    smtp.open_timeout = 5
    smtp.read_timeout = 10
    context = OpenSSL::SSL::SSLContext.new
    context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    security == 'tls' ? smtp.enable_tls(context) : smtp.enable_starttls(context)
    if authentication == 'none'
      smtp.start(domain) { }
    else
      smtp.start(domain, username, password, authentication.to_sym) { }
    end
  end

  private

  def encryptor
    key = Rails.application.key_generator.generate_key('sietconnect-smtp-password-v1', 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end
end
