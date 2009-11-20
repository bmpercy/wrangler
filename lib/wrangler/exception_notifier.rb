module Wrangler
  # handles notifying (sending emails) for the wrangler gem. configuration for
  # the class is set in an initializer via the configure() method, e.g.
  #
  # Wrangler::ExceptionNotifier.configure do |config|
  #   config[:key] = value
  # end
  #
  # see README or source code for possible values and default settings
  #-----------------------------------------------------------------------------
  class ExceptionNotifier < ActionMailer::Base

    # smtp settings specific to this class; allows for changing settings
    # (e.g. from-address) to be different from other emails sent in your app
    @@smtp_settings_overrides = {}
    cattr_accessor :smtp_settings_overrides

    # Allows overriding smtp_settings without changing parent class' settings.
    # rails expects an instance method
    #-----------------------------------------------------------------------------
    def smtp_settings
      @@smtp_settings_overrides.reverse_merge @@smtp_settings
    end  

    # the default configuration
    @@config ||= {
      # who the emails will be coming from. if nil or missing or empty string,
      # effectively disables email notification
      :from_address => '',
      # array of addresses that the emails will be sent to. if nil or missing
      # or empty array, effectively disables email notification.
      :recipient_addresses => [],
      # what will show up at the beginning of the subject line for each email
      # sent note: will be preceded by "[<app_name (if any)>...", where app_name
      # is the :app_name config value from ExceptionHandler (or explicit
      # proc_name given to notify_on_error() method)
      :subject_prefix => "#{(defined?(Rails) ? Rails.env : RAILS_ENV).capitalize} ERROR",
      # can use this to define app-specific mail views using the same data
      # made available in exception_notification()
      :mailer_template_root => File.join(WRANGLER_ROOT, 'views')
    }

    cattr_accessor :config

    def self.configure(&block)
      yield @@config
    end

    self.template_root = config[:mailer_template_root]

    # form and send the notification email (note: this gets called indirectly
    # when you call ExceptionNotifier.deliver_exception_notification())
    #
    # arguments:
    #   - exception: the exception that was raised
    #   - proc_name: the name of the process in which the exception arised
    #   - backtrace: the stack trace from the exception (passing in excplicitly
    #                because serializing the exception does not preserve the
    #                backtrace (in case delayed_job is used to async the email)
    #   - status_code: the (string) http status code that the exception has been
    #                  mapped to. Optional, but no default is provided, so
    #                  no status code info will be contained in the email.
    #   - request_data: hash with relevant data from the request object.
    #                   Optional, but if not present, then assumed the exception
    #                   was not due to an http request and thus no request
    #                   data will be contained in the email.
    #   - request: the original request that resulted in the exception. may
    #              be nil and MUST be nil if calling this method with
    #              delayed_job. Optional.
    #---------------------------------------------------------------------------
    def exception_notification(exception, proc_name, backtrace,
                               status_code = nil,
                               request_data = nil,
                               request = nil)

      # don't try to send email if there are no from or recipient addresses
      if config[:from_address].nil? ||
         config[:from_address].empty? ||
         config[:recipient_addresses].nil? ||
         config[:recipient_addresses].empty?

        return nil
      end

      ensure_session_loaded(request)

      # NOTE: be very careful pulling data out of request in the view...it is
      # NOT cleaned, and may contain private data (e.g. passwords), so 
      # scrutinize any use of @request in the views!

      body_hash =
        { :exception =>    exception,
          :backtrace =>    backtrace,
          :status_code =>  status_code,
          :request_data => request_data,
          :request =>      request 
        }

      body_hash.merge! extract_data_from_request_data(request_data)
      from         config[:from_address]
      recipients   config[:recipient_addresses]
      subject      "[#{proc_name + (proc_name ? ' ' : '')}" +
                   "#{config[:subject_prefix]}] " +
                   "#{exception.class.name}: " +
                   "#{exception.message.inspect}"
      body         body_hash
      sent_on      Time.now
      content_type 'text/plain'
    end

    # helper to force loading of session data in case of lazy loading (Rails
    # 2.3). if the argument isn't a request object, then don't bother, cause
    # it won't have session.
    #---------------------------------------------------------------------------
    def ensure_session_loaded(request)
      request.session.inspect if !request.nil? && request.respond_to?(:session)
      true
    end

    # extract relevant (and serializable) data from a request object
    #---------------------------------------------------------------------------
    def extract_data_from_request_data(request_data)
      if request_data
        { :host => host_from_request_data(request_data),
          :protocol => protocol_from_request_data(request_data),
          :uri => uri_from_request_data(request_data)
        }
      else
        {}
      end
    end

    # extract the host from request object
    #---------------------------------------------------------------------------
    def host_from_request_data(request_data)
      request_data['HTTP_X_REAL_IP'] ||
        request_data['HTTP_X_FORWARDED_HOST'] ||
        request_data['HTTP_HOST']
    end

    # extract protocol from request object
    #---------------------------------------------------------------------------
    def protocol_from_request_data(request_data)
      request_data['SERVER_PROTOCOL']
    end

    # extract URI from request object
    #---------------------------------------------------------------------------
    def uri_from_request_data(request_data)
      request_data['REQUEST_URI']
    end

  end

end
