class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Leak <no-reply@leak.invalid>") }
  layout "mailer"
end
