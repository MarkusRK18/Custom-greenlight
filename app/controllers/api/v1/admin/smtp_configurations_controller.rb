# frozen_string_literal: true

module Api
  module V1
    module Admin
      class SmtpConfigurationsController < ApiController
        before_action { ensure_authorized('ManageSiteSettings') }

        def show
          render_data data: configuration.public_settings, status: :ok
        end

        def update
          config = configuration
          values = params.require(:smtp_configuration).permit(*SmtpConfiguration::PUBLIC_FIELDS, :password)
          values.delete(:password) if values[:password].blank?
          config.assign_attributes(values)
          config.password = nil if config.authentication == 'none'
          return render_error errors: config.errors.full_messages, status: :unprocessable_entity unless config.save

          render_data data: config.public_settings, status: :ok
        end

        def test_connection
          configuration.test_connection!
          render_data data: { message: 'SMTP connection and authentication succeeded.' }, status: :ok
        rescue StandardError => e
          render_error errors: "SMTP connection failed (#{e.class.name.demodulize}). Check the host, TLS mode and credentials.", status: :unprocessable_entity
        end

        def test_email
          config = configuration
          return render_error errors: 'Save and enable valid SMTP settings first.', status: :unprocessable_entity unless config.configured?

          # A test email is sent only to the administrator requesting it.
          SmtpTestMailer.with(provider: current_provider, recipient: current_user.email).connection_test.deliver_now
          render_data data: { message: "Test email accepted by SMTP for #{current_user.email}. Check your inbox and spam folder." }, status: :ok
        rescue StandardError => e
          render_error errors: "Test email failed (#{e.class.name.demodulize}). Check SMTP settings and sender permissions.", status: :unprocessable_entity
        end

        private

        def configuration
          SmtpConfiguration.for_provider(current_provider)
        end
      end
    end
  end
end
