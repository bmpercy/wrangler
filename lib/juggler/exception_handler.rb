module Juggler

  def self.http_status_codes
    {
      "400" => "Bad Request",
      "401" => "Unuthorized",
      "403" => "Forbidden",
      "404" => "Not Found",
      "405" => "Method Not Allowed",
      "410" => "Gone",
      "418" => "I'm a teapot", # a joke thing...just here for 'completeness'
      "422" => "Unprocessable Entity",
      "423" => "Locked",
      "500" => "Internal Server Error",
      "501" => "Not Implemented",
      "503" => "Service Unavailable"
    }
  end

  def self.codes_for_exception_classes
    classes = {
      # These are standard errors in rails / ruby
      NameError =>      "503",
      TypeError =>      "503",
      RuntimeError =>   "500",
      ArgumentError =>  "500",
      #TODO: rip these off too?...include and update comment if so
      # These are custom error names defined in lib/super_exception_notifier/custom_exception_classes
#      AccessDenied =>   "403",
#      PageNotFound =>   "404",
#      InvalidMethod =>  "405",
#      ResourceGone =>   "410",
#      CorruptData =>    "422",
#      NoMethodError =>  "500",
#      NotImplemented => "501",
#      MethodDisabled => "200",
      # the default mapping for an unrecognized exception class
      :default => "500",
    }

    # from exception_notification gem:
    # Highly dependent on the verison of rails, so we're very protective about these'
    classes.merge!({ ActionView::TemplateError => "500"})             if defined?(ActionView)       && ActionView.const_defined?(:TemplateError)
    classes.merge!({ ActiveRecord::RecordNotFound => "400" })         if defined?(ActiveRecord)     && ActiveRecord.const_defined?(:RecordNotFound)
    classes.merge!({ ActiveResource::ResourceNotFound => "404" })     if defined?(ActiveResource)   && ActiveResource.const_defined?(:ResourceNotFound)

    # from exception_notification gem:
    if defined?(ActionController)
      classes.merge!({ ActionController::UnknownController => "404" })          if ActionController.const_defined?(:UnknownController)
      classes.merge!({ ActionController::MissingTemplate => "404" })            if ActionController.const_defined?(:MissingTemplate)
      classes.merge!({ ActionController::MethodNotAllowed => "405" })           if ActionController.const_defined?(:MethodNotAllowed)
      classes.merge!({ ActionController::UnknownAction => "501" })              if ActionController.const_defined?(:UnknownAction)
      classes.merge!({ ActionController::RoutingError => "404" })               if ActionController.const_defined?(:RoutingError)
      classes.merge!({ ActionController::InvalidAuthenticityToken => "405" })   if ActionController.const_defined?(:InvalidAuthenticityToken)
    end

    return classes
  end

  

  # TODO: figure out what to do with this class (if anything). looksl ike all of the logic
  # has been pushed into the module that gets included by the controllers (cause its
  # methods reach into controller state a lot....:( so maybe just convert this to a
  # config-only class? and it gets read by the juggler module, but that's it?

  # TODO: comment me
  class ExceptionHandler

    # the default configuration
    @@config ||= {
      :app_name => 'MYAPP',
      :handle_local_errors => false,
      :handle_public_errors => true,
      # ignored if :handle_local_errors is false
      :notify_on_local_error => false,
      # ignored if :handle_public_errors is false
      :notify_on_public_error => true,
      :notify_on_background_error => true,
      :delayed_job_for_controller_errors => false,
      :delayed_job_for_non_controller_errors => false,
  
      # add/remove from this list as desired in environment configuration
      :error_class_status_codes => Juggler.codes_for_exception_classes,
      :http_status_codes => Juggler.http_status_codes,
      :notify_exception_classes => %w(),
      :notify_status_codes => %w( 405 500 503 ),
      :error_template_dir => File.join(RAILS_ROOT, 'app', 'views', 'error'),
      # these filter out any HTTP params that are undesired
      :request_env_to_skip => [ /^rack\./,
                                "action_controller.rescue.request",
                                "action_controller.rescue.response" ],
#     mapping from exception classes to templates (if desired), express
#     in absolute paths. use wildcards like on cmd line (glob-like), NOT
#     regexp-style
      :error_class_html_templates => {},
      :error_class_js_templates => {}

# TODO: could also add manual mappings from status_codes to templates...meh.

# TODO: only include this if we use it
#      :verbose = false
    }

    cattr_accessor :config

  # configuration:
  # use delayed_job or not if in controller
  # use delayed_job or not if in non-controller
  # on/off for local requests
  # from address
  # recipient addresses
  # list of exceptions and the http error codes they map to
  # list of exceptions to notify for (allow :only and :except behavior)
  # list of http error codes to notify for (allow :only and :except behavior)
  # application name
  # 





    # allows for overriding default configuration settings.
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
    # Juggler::ExceptionHandler.configure do |handler_config|
    #   handler_config[:key1] = value1
    #   handler_config[:key2] = value2
    #   handler_config[:key_for_a_hash].merge! :subkey => value
    #   handler_config[:key_for_an_array] << another_value
    # end
    #
    # OR
    #
    # Juggler::ExceptionHandler.configure do |handler_config|
    #   handler_config.merge! :key1 => value1,
    #                         :key2 => value2,
    #   handler_config[:key_for_a_hash].merge! :subkey => value
    #   handler_config[:key_for_an_array] << another_value
    # end
    # 
    # NOTE: sure, you can change this configuration on the fly in your app, but
    # we don't recommend it. plus, if you do and you're using delayed_job, there
    # may end up being configuration differences between the rails process and
    # the delayed_job process, resulting in unexpected behavior. so recommend
    # you just modify this in the environment config files...or if you're doing
    # something sneaky, you're on your own.
    #-----------------------------------------------------------------------------
    def self.configure(&block)
      yield @@config
    end

  # TODO: allow non-controller cases...maybe copy the cool approach to giving
  # a method like notify_on_error { ... } that runs the block and notifies
  # if an exception bubbles up

  # TODO: allow configuring different settings for each controller? not too
  # important for us...

  # TODO: allow for html vs. js to work smoothly...just pick the right template
  # based on the accepts value in request

  # TODO: set up some default locations to look for error code pages
  # e.g public/###.html , app/views/errors/###.html.erb
  # 1) public/###.html (or ###.js???)
  # 2) <template dir in config>/###.html.erb / js.erb
  # 3) gem/rails/app/views/exception_handler/###.html (or ###.js???)


  end
end
