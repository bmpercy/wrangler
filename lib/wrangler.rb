require 'wrangler/wrangler_helper.rb'
require 'wrangler/exception_handler.rb'

# the notifier is still rails-dependent...
if defined?(Rails)
  require 'wrangler/exception_notifier.rb'
end
require 'wrangler/wrangler_exceptions.rb'

module Wrangler

  def self.included(base)
    # only add in the controller-specific methods if the including class is one
    if defined?(Rails) && class_has_ancestor?(base, ActionController::Base)
      base.send(:include, ControllerMethods)

      # conditionally including these methods (each wrapped in a separate
      # module) based on the configuration of whether to handle exceptions in
      # the given environment or not. this allows the default implementation
      # of the two rescue methods to run when Wrangler-based exception handling
      # is disabled.

      if Wrangler::ExceptionHandler.config[:handle_public_errors]
        Rails.logger.info "Configuring #{base.name} with Wrangler's rescue_action_in_public"
        base.send(:include, PublicControllerMethods)
      else
        Rails.logger.info "NOT Configuring #{base.name} with Wrangler's rescue_action_in_public"
      end

      if Wrangler::ExceptionHandler.config[:handle_local_errors]
        Rails.logger.info "Configuring #{base.name} with Wrangler's rescue_action_locally"
        base.send(:include, LocalControllerMethods)
      else
        Rails.logger.info "NOT configuring #{base.name} with Wrangler's rescue_action_locally"
      end
    end
  end


  # methods to only be included into a controller if Wrangler is configured to
  # handle exceptions for public reqeusts. (Conditionally included into
  # controllers in the Wrangler::included() method).
  #-----------------------------------------------------------------------------
  module PublicControllerMethods
    # override default behavior and let Wrangler handle the exception for
    # public (non-local) requests.
    #---------------------------------------------------------------------------
    def rescue_action_in_public(exception)
      handle_exception(exception, :request => request,
                       :render_errors => true)
    end
  end


  # methods to only be included into a controller if Wrangler is configured to
  # handle exceptions for local reqeusts. (Conditionally included into
  # controllers in the Wrangler::included() method).
  #-----------------------------------------------------------------------------
  module LocalControllerMethods
    # override default behavior and let Wrangler handle the exception for
    # local requests.
    #---------------------------------------------------------------------------
    def rescue_action_locally(exception)
      handle_exception(exception, :request => request,
                       :render_errors => true)
    end
  end


  # module of instance methods to be added to the class including Wrangler
  # only if the including class is a rails controller class
  #-----------------------------------------------------------------------------
  module ControllerMethods

    # called by rails if the exception has already been handled (e.g. by
    # calling the rescue_from method in a controller and rendering a response)
    #---------------------------------------------------------------------------
    def rescue_with_handler(exception)
      to_return = super
      if to_return &&
           (
             (local_request? && Wrangler::ExceptionHandler.config[:handle_local_errors]) ||
             (!local_request? && Wrangler::ExceptionHandler.config[:handle_public_errors])
           )

        handle_exception(exception, :request => request,
                                    :render_errors => false)
      end
      to_return
    end


    # select the proper file to render and do so. if the usual places don't
    # turn up an appropriate template (see README), then fall back on
    # an app-specific default error page or the ultimate back up gem default
    # page.
    #---------------------------------------------------------------------------
    def render_error_template(exception, status_code)
      file_path = get_view_path_for_exception(exception, status_code)
      
      # if that didn't work, fall back on configured app-specific default
      if file_path.blank? || !File.exists?(file_path)
        file_path = config[:default_error_template]

        log_error(["Could not find an error template in the usual places " +
                  "for exception #{exception.class}, status code " +
                  "#{status_code}.",
                  "Trying to default to app-specific default: '#{file_path}'"])
      end

      # as a last resort, just render the gem's 500 error
      if file_path.blank? || !File.exists?(file_path)
        file_path = config[:absolute_last_resort_default_error_template]

        log_error("Still no template found. Using gem default of " +
                  file_path)
      end

      log_error("Will render error template: '#{file_path}'")

      render :file => file_path,
             :status => status_code
    end


    # select the appropriate view path for the exception/status code. see
    # README or the code for the different attempts that are made to find
    # a template.
    #---------------------------------------------------------------------------
    def get_view_path_for_exception(exception, status_code)

      # maintenance note: this method has lots of RETURN statements, so be
      # a little careful, but basically, it returns as soon as it finds a
      # file match, so there shouldn't be any processing to perform after
      # a match is found. any such logic does not belong in this method

      if exception.is_a?(Class)
        exception_class = exception
      else
        exception_class = exception.class
      end

      # Note: this converts "::" to "/", so views need to be nested under
      # exceptions' modules if appropriate
      exception_filename_root = exception_class.name.underscore

      template_mappings = nil
      case request.format
      when /html/
        response_format = 'html'
        template_mappings = config[:error_class_html_templates]
      when /js/
        response_format = 'js'
        template_mappings = config[:error_class_js_templates]
      when /xml/
        'xml'
      end
      format_extension_pattern = ".#{response_format || ''}*"

      if template_mappings

        # search for direct mapping from exception name to error template

        if template_mappings[exception_class]
          error_file = template_mappings[exception_class]

          return error_file if File.exists?(error_file)

          log_error("Found mapping from exception class " +
                    "#{exception_class.name} to error file '#{error_file}', " +
                    "but error file was not found")
        end

        # search for mapping from an ancestor class to error template

        ancestor_class =
          Wrangler::class_has_ancestor?(exception_class.superclass,
                                       template_mappings)

        if ancestor_class
          error_file = template_mappings[ancestor_class]

          return error_file if File.exists?(error_file)

          log_error("Found mapping from ancestor exception class " +
                    "#{ancestor_class.name} to error file '#{error_file}', " +
                    "but error file was not found")
        end

      end # end if template_mappings

      # search for a file named after the exception in one of the search dirs

      search_paths = [ config[:error_template_dir],
                       File.join(RAILS_ROOT, 'public'),
                       File.join(WRANGLER_ROOT, 'rails', 'app', 'views', 'wrangler')
                     ]

      # find files in specified directory like 'exception_class_name.format', e.g.
      # standard_error.html or standard_error.js.erb
      exception_pattern = "#{exception_filename_root}#{format_extension_pattern}"
      file_path = find_file_matching_pattern(search_paths, exception_pattern)

      return file_path if file_path

      # search for a file named after the error status code in search dirs

      status_code_pattern = "#{status_code}#{format_extension_pattern}"
      file_path = find_file_matching_pattern(search_paths, status_code_pattern)

      return file_path if file_path

      # search for a file named after ancestors of the exception in search dirs

      # look through exception's entire ancenstry to see if there's a matching
      # template in the search directories
      curr_ancestor = exception_class.superclass
      while curr_ancestor
        # find files in specified directory like 'exception_class_name.format', e.g.
        # standard_error.html or standard_error.js.erb
        exception_pattern =
          "#{curr_ancestor.name.underscore}#{format_extension_pattern}"
        file_path = find_file_matching_pattern(search_paths, exception_pattern)

        return file_path if file_path

        curr_ancestor = curr_ancestor.superclass
      end

      # didn't find anything
      return nil
    end

  end # end ControllerMethods module


  # extract a hash of relevant (and serializable) parameters from a request
  # NOTE: will obey +filter_paramters+ on any class including the module,
  # avoid logging any data in the request that the app wouldn't log itself.
  # +filter_paramters+ must follow the rails convention of returning
  # the association but with the value obscured in some way
  # (e.g. "[FILTERED]"). see +filter_paramter_logging+ .
  #-----------------------------------------------------------------------------
  def request_data_from_request(request)
    return nil if request.nil?

    request_data = {}
    request.env.each_pair do |k,v|
      next if skip_request_env?(k)

      if self.respond_to?(:filter_parameters)
        request_data.merge! self.send(:filter_parameters, k => v)
      else
        request_data.merge! k => v
      end
    end

    request_params = {}
    if self.respond_to?(:filter_parameters)
      request_params.merge!(
                    filter_parameters(request.env['action_controller.request.query_parameters'])
                    )
      request_params.merge!(
                    filter_parameters(request.env['action_controller.request.request_parameters'])
                    )
    else
      request_params.merge! request.env['action_controller.request.query_parameters']
      request_params.merge! request.env['action_controller.request.request_parameters']
    end

    request_data.merge! :params => request_params unless request_params.blank?

    return request_data
  end


  # determine if the request env param should be ommitted from the request
  # data object, as specified in config (either for aesthetic reasons or
  # because the param won't serialize well).
  #---------------------------------------------------------------------------
  def skip_request_env?(request_param)
    skip_env = false
    Wrangler::ExceptionHandler.config[:request_env_to_skip].each do |pattern|
      if (pattern.is_a?(String) && pattern == request_param) ||
         (pattern.is_a?(Regexp) && pattern =~ request_param)
        skip_env = true
        break
      end
    end

    return skip_env
  end

end # end Wrangler module
