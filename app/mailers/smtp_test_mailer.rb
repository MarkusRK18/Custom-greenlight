# frozen_string_literal: true

class SmtpTestMailer < ApplicationMailer
  def connection_test
    mail(to: params[:recipient], subject: 'SIETConnect SMTP test') do |format|
      format.text { render plain: 'SIETConnect successfully submitted this test email using your saved SMTP settings.' }
    end
  end
end
