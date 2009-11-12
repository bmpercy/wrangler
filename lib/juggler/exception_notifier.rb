module Juggler
  # handles notifying (sending emails) for the juggler gem. configuration for
  # the class is set in an initializer via the configure() method, e.g.
  #
  # Juggler::ExceptionNotifier.configure do |config|
  #   config[:key] = value
  # end
  #
  # see README or source code for possible values and default settings
  #-----------------------------------------------------------------------------
  class ExceptionNotifier < ActionMailer::Base
    # the default configuration
    @@config ||= {
      :from_address => '',
      :recipient_addresses => [],
      # note: will be preceded by proc_name (if any)
      :subject_prefix => "#{(defined?(Rails) ? Rails.env : RAILS_ENV).capitalize} ERROR",
      # can define app-specific mail views using the data available in
      # exception_notification()
      :mailer_template_root => File.join(JUGGLER_ROOT, 'views')
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

      puts "\n\n\nTODO: in exception notifier's exception notification method!\n\n"
      puts "TODO: exception is #{exception}"
      puts "TODO: proc_name is #{proc_name}"

      ensure_session_loaded(request)

      # TODO: subject support for non-controller-based exceptions

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

    # TODO maybe 'sanitize backtrace' as in exception_notifier.rb (looks like it's just
    # masking the rails dir location by substituting it with "[RAILS ROOT]", i guess
    # for security??? (uses the 'pathname' lib (Pathname is the class))

      # TODO: make sure that the smtp_settings is changed to send from the
      # monitor@ account instead of notice@...

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
