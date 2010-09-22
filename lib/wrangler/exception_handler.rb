module Wrangler

  # A utility method that should only be used internal to wrangler. don't call
  # this; it should only be called once by the Config class and you can get/set
  # it there. returns a mapping from exception classes to http status codes
  #-----------------------------------------------------------------------------
  def self.codes_for_exception_classes
    classes = {
      # These are standard errors in rails / ruby
      NameError.name =>      "503",
      TypeError.name =>      "503",
      RuntimeError.name =>   "500",
      ArgumentError.name =>  "500",
      # the default mapping for an unrecognized exception class
      :default => "500"
    }

    # from exception_notification gem:
    # Highly dependent on the verison of rails, so we're very protective about these'
    classes.merge!({ ActionView::TemplateError.name => "500"})             if defined?(ActionView)       && ActionView.const_defined?(:TemplateError)
    classes.merge!({ ActiveRecord::RecordNotFound.name => "400" })         if defined?(ActiveRecord)     && ActiveRecord.const_defined?(:RecordNotFound)
    classes.merge!({ ActiveResource::ResourceNotFound.name => "404" })     if defined?(ActiveResource)   && ActiveResource.const_defined?(:ResourceNotFound)

    # from exception_notification gem:
    if defined?(ActionController)
      classes.merge!({ ActionController::UnknownController.name => "404" })          if ActionController.const_defined?(:UnknownController)
      classes.merge!({ ActionController::MissingTemplate.name => "404" })            if ActionController.const_defined?(:MissingTemplate)
      classes.merge!({ ActionController::MethodNotAllowed.name => "405" })           if ActionController.const_defined?(:MethodNotAllowed)
      classes.merge!({ ActionController::UnknownAction.name => "501" })              if ActionController.const_defined?(:UnknownAction)
      classes.merge!({ ActionController::RoutingError.name => "404" })               if ActionController.const_defined?(:RoutingError)
      classes.merge!({ ActionController::InvalidAuthenticityToken.name => "405" })   if ActionController.const_defined?(:InvalidAuthenticityToken)
    end

    return classes
  end

  # class that holds configuration for the exception handling logic. may also
  # include a helper method or two, but the main interaction with
  # +ExceptionHandler+ is setting and getting config, e.g.
  #
  #   Wrangler::ExceptionHandler.configure do |handler_config|
  #     handler_config.merge! :key => value
  #   end
  #-----------------------------------------------------------------------------
  class ExceptionHandler

    # the default configuration
    @@config ||= {
      :app_name => '',
      :handle_local_errors => false,
      :handle_public_errors => true,
      # send email for local reqeusts. ignored if :handle_local_errors false
      :notify_on_local_error => false,
      # send email for public requests. ignored if :handle_public_errors false
      :notify_on_public_error => true,
      # send email for exceptions caught outside of a controller context
      :notify_on_background_error => true,
      # configure regular expressions for specific HTTP headers, which if they
      # match will NOT send notification emails (e.g. for filtering out crazy
      # browsers).
      # array of hashes, each with one key (http header string) and a value
      # (regexp to match in http header string). this allows for more than one
      # regexp to be specified for the same header if that's more convenient.
      # any one pattern match will block notification.
      # note that this looks in all request headers, including query params
      # (e.g. form fields, url query params)
      :block_notify_on_request_headers => [],
      # configure whether to send emails synchronously or asynchronously
      # using delayed_job (these can be true even if delayed job is not
      # installed, in which case, will just send emails synchronously anyway)
      :delayed_job_for_controller_errors => true,
      :delayed_job_for_non_controller_errors => true,
      # mappings from exception classes to http status codes (see above)
      # add/remove from this list as desired in environment configuration
      # note that the keys are String names of the classes, not the class
      # constants themselves
      # (e.g. "StandardError" => "500",    and _NOT_ StandardError => "500")
      :error_class_status_codes => Wrangler::codes_for_exception_classes,
      # explicitly indicate which exceptions to send email notifications for
      :notify_exception_classes => %w(),
      # indicate which http status codes should result in email notification
      :notify_status_codes => %w( 405 500 503 ),
      # where to look for app-specific error page templates (ones you create
      # yourself, for example...there are some defaults in this gem you can
      # use as well...and that are configured already by default)
      :error_template_dir => (defined?(RAILS_ROOT) ? File.join(RAILS_ROOT, 'app', 'views', 'error') : nil),
      # explicit mappings from exception class to arbitrary error page
      # templates, different set for html and js responses (Wrangler determines
      # which to use automatically, so you can have an entry in both
      # hashes for the same error class)
      # note that the keys are String names of the classes, not the class
      # constants themselves
      # (e.g. "StandardError" => "file",    and _NOT_ StandardError => "file")
      :error_class_html_templates => {},
      :error_class_js_templates => {},
      # you can specify options to pass to the render() call when rendering
      # error page for errors. This is applied globally, so plan accordingly
      # (one good option is to pass in :layout => 'my_layout' so your app
      # layout gets applied to the error templates)
      :render_error_options => {},
      # you can specify a fallback failsafe error template to render if
      # no appropriate template is found in the usual places (you shouldn't
      # rely on this, and error messages will be logged if this template is
      # used). note: there's an even more failsafe template included in the
      # gem (absolute_last_resort...) below, but DON'T CHANGE IT!!!
      :default_error_template => '',
      # these filter out any HTTP params that are undesired
      :request_env_to_skip => [ /^rack\./,
                                "action_controller.rescue.request",
                                "action_controller.rescue.response" ],
      # mapping from exception classes to templates (if desired), express
      # in absolute paths. use wildcards like on cmd line (glob-like), NOT
      # regexp-style

      # just DON'T change this! this is the error template of last resort!
      # if you do change this, you really should have a good reason for it and
      # really know what you're doing. really.
      :absolute_last_resort_default_error_template =>
        File.join(WRANGLER_ROOT,'rails','app','views','wrangler','500.html'),
      # allows for inserting additional data/comments/status/environment into
      # the notification emails. possibilities include fetching the release number,
      # patch info, current state of different services....
      # pass a proc instance that accepts a single
      # argument, the request object (if any).
      # (e.g. +Proc.new { |request| puts "request is: #{request}" }+, but don't
      # do that, that would be redundant, silly and not secure).
      # NOTE: +request+ can be nil (if background process, for example), so
      # implement accordingly
      :call_for_supplementary_info => nil
    }

    # give access to config
    #-----------------------------------------------------------------------------
    def self.config
      @@config
    end


    # Allows for overriding default configuration settings.
    # in your environment.rb or environments/<env name>.rb, use a block that
    # accepts one argument
    # * recommend against naming it 'config' as you will probably be calling it
    #   within the config block in env.rb...):
    # * note that some of the config values are arrays or hashes; you can
    #   overwrite them completely, delete or insert/merge new entries into the
    #   default values as you see fit...but in most cases, recommend AGAINST
    #   overwriting the arrays/hashes completely unless you don't want to
    #   take advantage of lots of out-of-the-box config
    #
    #   Wrangler::ExceptionHandler.configure do |handler_config|
    #     handler_config[:key1] = value1
    #     handler_config[:key2] = value2
    #     handler_config[:key_for_a_hash].merge! :subkey => value
    #     handler_config[:key_for_an_array] << another_value
    #   end
    #
    # OR
    #
    #   Wrangler::ExceptionHandler.configure do |handler_config|
    #     handler_config.merge! :key1 => value1,
    #                           :key2 => value2,
    #     handler_config[:key_for_a_hash].merge! :subkey => value
    #     handler_config[:key_for_an_array] << another_value
    #   end
    #
    # *NOTE*: sure, you can change this configuration on the fly in your app, but
    # we don't recommend it. plus, if you do and you're using delayed_job, there
    # may end up being configuration differences between the rails process and
    # the delayed_job process, resulting in unexpected behavior. so recommend
    # you just modify this in the environment config files...or if you're doing
    # something sneaky, you're on your own.
    #-----------------------------------------------------------------------------
    def self.configure(&block)
      yield @@config
    end


    # translate the exception class to an http status code, using default
    # code (set in config) if the exception class isn't excplicitly mapped
    # to a status code in config
    #---------------------------------------------------------------------------
    def self.status_code_for_exception(exception)
      if exception.respond_to?(:status_code)
        return exception.status_code
      else
        return config[:error_class_status_codes][exception.class.name] ||
               config[:error_class_status_codes][:default]
      end
    end

  end # end ExceptionHandler class

  ##############################################################################
  # actual exception handling code
  ##############################################################################

  # make all of these instance methods also module functions
  module_function

  # execute the code block passed as an argument, and follow notification
  # rules if an exception bubbles out of the block.
  #
  # == arguments
  # [proc_name]  a name for the chunk of code you're running, included in logs
  #              and in the email notifications' subject line. optional, default
  #              is nil (nothing will be displayed).
  # [message]  a message to include in any logs regarding exceptions thrown.
  #            useful to explain what the context of the code was to help
  #            diagnose. optional, default is nil (no message will be displayed
  #            other than the exception's own message).
  # 
  # == return value
  # * if an exception bubbles out of the block, the exception is re-raised to
  #   calling code.
  # * otherwise, returns nil
  #-----------------------------------------------------------------------------
  def notify_on_error(proc_name = nil, message = nil, &block)
    begin
      yield
    rescue => exception
      options = {}
      options.merge! :proc_name => proc_name unless proc_name.nil?
      options.merge! :error_messages => message unless message.nil?
      handle_exception(exception, options)
    end

    return nil
  end


  # publicly available method for explicitly telling wrangler to handle
  # a specific error condition without an actual exception. it's useful if you
  # want to send a notification after detecting an error condition, but don't
  # want to interrupt the stack by raising an exception. if you did catch an
  # exception and want to do somethign similar, just call handle_exception
  # diretly.
  #
  # the error condition will get logged and may result in notification,
  # according to configuration see notify_on_exception?
  #
  # == arguments
  # [error_messages] a message or array of messages (each gets logged on
  #                  separate log call) capturing the error condition that
  #                  occurred. this will get logged AND sent in any
  #                  notifications sent
  #
  # == options
  # also, any of the options accepted by handle_exception
  #-----------------------------------------------------------------------------
  def handle_error(error_messages, options = {})
    options.merge! :error_messages => error_messages
    handle_exception(nil, options)
  end


  # the main exception-handling method. decides whether to notify or not,
  # whether to render an error page or not, and to make it happen.
  #
  # == arguments
  # [exception] the exception that was caught. can be nil, but should
  #             only be nil if notifications should always be sent,
  #             as notification rules are bypassed this case
  #
  # == options
  # [error_messages] any additional message to log and send in notification.
  #                  can also be an array of messages (each gets logged
  #                  separately)
  # [request] the request object (if any) that resulted in the exception
  # [render_errors] boolean indicating if an error page should be rendered
  #                 or not (Rails only). default => false
  # [proc_name] a string representation of the process/app that was running
  #             when the exception was raised. default value is
  #             Wrangler::ExceptionHandler.config[:app_name].
  #-----------------------------------------------------------------------------
  def handle_exception(exception, options = {})
    request = options[:request]
    render_errors = options[:render_errors] || false
    proc_name = options[:proc_name] || config[:app_name]
    error_messages = options[:error_messages] || ['']

    error_messages = [error_messages] unless error_messages.is_a?(Array)

    if exception.respond_to?(:backtrace)
      backtrace = exception.backtrace
    else
      backtrace = caller
    end

    # extract the relevant request data and also filter out any params
    # that should NOT be logged/emailed (passwords etc.)
    request_data = request_data_from_request(request) unless request.nil?

    supplementary_info = nil

    unless config[:call_for_supplementary_info].nil?
      supplementary_info = config[:call_for_supplementary_info].call(request)
      supplementary_info = [supplementary_info] unless supplementary_info.is_a?(Array)
    end

    unless supplementary_info.blank?
      error_messages << "Supplementary info:"
      error_messages += supplementary_info
    end

    if exception.nil?
      exception_classname = nil
      status_code = nil
      log_error error_messages.inspect
      log_error backtrace
      log_error "Request params were:"
      log_error request_data.to_yaml
      error_string = error_messages.shift
    else
      status_code =
        Wrangler::ExceptionHandler.status_code_for_exception(exception)

      log_exception(exception, request_data, status_code, error_messages)

      if exception.is_a?(Class)
        exception_classname = exception.name
      else
        exception_classname = exception.class.name
      end

      if exception.respond_to?(:message)
        error_string = exception.message
      else
        error_string = exception.to_s
      end
    end

    if send_notification?(exception, request, status_code)
      if notify_with_delayed_job?
        # don't pass in request as it contains not-easily-serializable stuff
        log_error "Wrangler sending email notification asynchronously"
        Wrangler::ExceptionNotifier.send_later(:deliver_exception_notification,
                                              exception_classname,
                                              error_string,
                                              error_messages,
                                              proc_name,
                                              backtrace,
                                              supplementary_info,
                                              status_code,
                                              request_data)
      else
        log_error "Wrangler sending email notification synchronously"
        Wrangler::ExceptionNotifier.deliver_exception_notification(exception_classname,
                                         error_string,
                                         error_messages,
                                         proc_name,
                                         backtrace,
                                         supplementary_info,
                                         status_code,
                                         request_data,
                                         request)
      end
    end

    if render_errors
      render_error_template(exception, status_code)
    end

  rescue Exception => unhandled_exception
    # if it looks like a temporary error interacting with SMTP, then enqueue
    # the error using delayed job if possible
    # (testing by name this way in case the exception isn't loaded into
    # environment, which would cause a NameError and be counterproductive...)
    if unhandled_exception.class.name == 'Net::SMTPAuthenticationError' &&
       Wrangler::ExceptionNotifier.respond_to?(:send_later)

      log_error "Wrangler failed to send error notification: #{unhandled_exception.class.name}:"
      log_error "  #{unhandled_exception.to_s}"

      # note: this is specific to an old-ish version of delayed job...should
      # make wrangler compatible with the old and the new...
      log_error "Wrangler attempting to send via delayed job"
        Wrangler::ExceptionNotifier.send_later(:deliver_exception_notification,
                                              exception_classname,
                                              error_string,
                                              error_messages,
                                              proc_name,
                                              backtrace,
                                              supplementary_info,
                                              status_code,
                                              request_data)
    else
      log_error "/!\\ FAILSAFE /!\\ Wrangler encountered an unhandled exception " +
                "while trying to handle an error. The arguments it received " +
                "were:"
      log_error "  exception: #{exception.inspect}"
      log_error "  options: #{options.inspect}"
      log_error "The unhandled error encountered was #{unhandled_exception.class.name}:"
      log_error "  #{unhandled_exception.to_s}"
    end
  end


  # determine if a notificaiton should be sent
  #-----------------------------------------------------------------------------
  def send_notification?(exception = nil, request = nil, status_code = nil)
    send_notification = notify_in_context?

    if !send_notification
      log_error("Will not notify because notify_in_context? returned false")
    end

    if send_notification && !exception.nil?
      send_notification &&= notify_on_exception?(exception, status_code)
      if !send_notification
        log_error("Will not notify because notify_on_exception? returned false")
      end
    end

    if send_notification && !request.nil?
      config[:block_notify_on_request_headers].each do |headers_and_patterns|
        headers_and_patterns.each_pair do |header, regexp|
          # only send notification if the header does NOT match the regexp
          if request.env.include?(header)
            send_notification &&= (regexp !~ request.env[header])
          end
          if request.env['action_controller.request.query_parameters'].include?(header)
            send_notification &&= (regexp !~ request.env['action_controller.request.query_parameters'][header])
          end
          if request.env['action_controller.request.request_parameters'].include?(header)
            send_notification &&= (regexp !~ request.env['action_controller.request.request_parameters'][header])
          end
        end
      end
      if !send_notification
        log_error "Will not notify because :block_notify_on_request_headers was configured to block this request"
      end
    end

    return send_notification
  end


  # determine if the current context (+local?+, +background+) indicates that a
  # notification should be sent. this applies all of the rules around
  # notifications EXCEPT for what the current exception or status code is
  # (see +notify_on_exception?+ for that)
  #-----------------------------------------------------------------------------
  def notify_in_context?
    if self.respond_to?(:local_request?)
      if (local_request? && config[:notify_on_local_error]) ||
          (!local_request? && config[:notify_on_public_error])
        notify = true
      else
        notify = false
      end
    else
      notify = config[:notify_on_background_error]
    end

    return notify
  end


  # determine if the app is configured to notify for the given exception or
  # status code
  #-----------------------------------------------------------------------------
  def notify_on_exception?(exception, status_code = nil)
    # first determine if we're configured to notify given the context of the
    # exception
    notify = notify_in_context?

    # now if config says notify in this case, check if we're configured to
    # notify for this exception or this status code
    return notify &&
      (config[:notify_exception_classes].include?(exception.class) ||
       config[:notify_status_codes].include?(status_code))
  end

  # determine if email should be sent with delayed job or not (delayed job
  # must be installed and config set to use delayed job
  #-----------------------------------------------------------------------------
  def notify_with_delayed_job?
    use_dj = false

    if self.is_a?(ActionController::Base)
      if config[:delayed_job_for_controller_errors] &&
          ExceptionNotifier.respond_to?(:send_later)
        use_dj = true
      else
        use_dj = false
      end
    else
      if config[:delayed_job_for_non_controller_errors] &&
          ExceptionNotifier.respond_to?(:send_later)
        use_dj = true
      else
        use_dj = false
      end
    end

    return use_dj
  end

end
