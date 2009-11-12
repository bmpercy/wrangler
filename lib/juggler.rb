require 'juggler/juggler_helper.rb'
require 'juggler/exception_handler.rb'
require 'juggler/exception_notifier.rb'

module Juggler

  def self.included(base)

    # only add in the controller-specific methods if the including class is one
    if class_has_ancestor?(base, ActionController::Base)

      # check the global configuration regarding exception handling. if config
      # says not to handle exceptions in public or locally, then fall back on
      # default exception handling without Juggler
#      unless Juggler::ExceptionHandler.config[:handle_public_errors]

#        puts "\n\nTODO: removing rescue_action_in_public from CMs"

#        ControllerMethods.send(:remove_method, :rescue_action_in_public)

#        puts "TODO: is the method gone?: #{ControllerMethods.instance_methods.include?('rescue_action_in_public') ? 'FALSE' : 'TRUE'}"
#      else
#        puts "\n\nTODO: NOT removing rescue_action_in_public from CMs"
#      end

#      unless Juggler::ExceptionHandler.config[:handle_local_errors]
#        puts "\n\nTODO: removing rescue_action_locally from CMs"
#        puts "TODO: is the method there?: #{ControllerMethods.instance_methods.include?('rescue_action_locally') ? 'TRUE' : 'FALSE'}"
#        puts "TODO: all methods: #{ControllerMethods.instance_methods.sort.to_yaml}"

#        ControllerMethods.send(:remove_method, :rescue_action_locally)
#        end

#        ControllerMethods.send(:remove_method, :rescue_action_locally)
#      else
#        puts "\n\nTODO: NOT removing rescue_action_locally from CMs"
#      end

      puts "\n\nTODO: BEFORE does base contain rescue_action_in_public?: #{base.instance_methods.include?('rescue_action_in_public') ? 'TRUE' : 'FALSE'}"
      puts "\n\nTODO: BEFORE does base contain rescue_action_locally?: #{base.instance_methods.include?('rescue_action_locally') ? 'TRUE' : 'FALSE'}"

      base.send(:include, ControllerMethods)

      puts "\n\nTODO: AFTER does base contain rescue_action_in_public?: #{base.instance_methods.include?('rescue_action_in_public') ? 'TRUE' : 'FALSE'}"
      puts "\n\nTODO: AFTER does base contain rescue_action_locally?: #{base.instance_methods.include?('rescue_action_locally') ? 'TRUE' : 'FALSE'}"
    end

    puts "\n\nTODO: juggler has been included into #{base.name}!\n\n"
  end

  # module of instance methods to be added to the class including Juggler
  # only if the including class is a rails controller class
  #-----------------------------------------------------------------------------
  module ControllerMethods

    # called by rails if the exception has already been handled (e.g. by
    # calling the rescue_from method in a controller and rendering a response)
    #---------------------------------------------------------------------------
    def rescue_with_handler(exception)
      to_return = super
      if to_return
        handle_exception(exception, :request => request,
                                    :render_errors => false)
      end
      to_return
    end

    # conditionally adding these methods so that the exception handling is
    # only activated if configured to do so. these are the methods that rails
    # looks for to override default behavior
    #---------------------------------------------------------------------------
    if Juggler::ExceptionHandler.config[:handle_public_errors]

      puts "\n\nTODO: adding in the public handler!\n\n"

      def rescue_action_in_public(exception)

        puts "\n\nTODO: rescuing in public!\n\n"

        handle_exception(exception, :request => request,
                                    :render_errors => true)
      end

    else

      puts "\n\nTODO: NOT adding in the local handler!\n\n"


    end
    if Juggler::ExceptionHandler.config[:handle_local_errors]

      puts "\n\nTODO: adding in the local handler!\n\n"

      def rescue_action_locally(exception)

        puts "\n\nTODO: rescuing locally!\n\n"

        handle_exception(exception, :request => request,
                                    :render_errors => true)
      end
    else
      puts "\n\nTODO: NOT adding in the local handler!\n\n"
    end

    # extract a hash of relevant (and serializable) parameters from a request
    #---------------------------------------------------------------------------
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

      params = {}
      # think adding these both is the right thing to do...
      # TODO: test with GET (works) and POST/PUT/DELETE (???)
      if self.respond_to?(:filter_parameters)
        params.merge!(
                      filter_parameters(request.env['action_controller.request.query_parameters'])
                      )
        params.merge!(
                      filter_parameters(request.env['action_controller.request.request_parameters'])
                      )
      else
        params.merge! request.env['action_controller.request.query_parameters']
        params.merge! request.env['action_controller.request.request_parameters']
      end

      request_data.merge! :params => params unless params.blank?

      return request_data
    end

    # determine if the request env param should be ommitted from the request
    # data object, as specified in config (either for aesthetic reasons or
    # because the param won't serialize well).
    #---------------------------------------------------------------------------
    def skip_request_env?(request_param)
      skip_env = false
      Juggler::ExceptionHandler.config[:request_env_to_skip].each do |pattern|
        if (pattern.is_a?(String) && pattern == request_param) ||
           (pattern.is_a?(Regexp) && pattern =~ request_param)
          skip_env = true
          break
        end
      end

      return skip_env
    end

    # select the proper file to render and do so
    #---------------------------------------------------------------------------
    def render_error_template(exception, status_code)
      # TODO: instead of raising exception, log error, send notification but pick
      # a default static file or template specified in config by user, and
      # if that fails, put a hardcoded path here and make sure that file is
      # in the gem

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

      puts "\n\nTODO: going to render error using #{file_path}"

      # TODO: try with and without layout...
      render :file => file_path,
             :status => status_code
    end

    # TODO: put this in the README as well

    # select the appropriate view path for the exception/status code
    #
    # rules:
    # 1) if there is an explicit mapping from this exception to an error
    #    page in :error_class_xxx_templates, use that
    # 2) if there is a mapping in :error_class_templates for which this
    #    exception returns true to an is_a? call, use that
    # 3) if there is a file/template corresponding to the exception
    #    name (underscorified) in one of the following locations, use that:
    #   a) config[:error_template_dir]/
    #   b) RAILS_ROOT/public/
    #   c) JUGGLER_ROOT/rails/app/views/juggler/
    # 4) if there is a file/template corresponding to the status code
    #    (e.g. named ###.html.erb where ### is the status code) in one
    #    of the following locations, use that:
    #   a) config[:error_template_dir]/
    #   b) RAILS_ROOT/public/
    #   c) JUGGLER_ROOT/rails/app/views/juggler/
    # 5) if there is a file/template corresponding to a parent class name of
    #    the exception (underscorified) one of the following locations,
    #    use that:
    #   a) config[:error_template_dir]/
    #   b) RAILS_ROOT/public/
    #   c) JUGGLER_ROOT/rails/app/views/juggler/
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
          puts "\n\nTODO: found direct exception to template mapping!: '#{error_file}'"

          return error_file if File.exists?(error_file)

          log_error("Found mapping from exception class " +
                    "#{exception_class.name} to error file '#{error_file}', " +
                    "but error file was not found")
        end

        # search for mapping from an ancestor class to error template

        ancestor_class =
          Juggler::class_has_ancestor?(exception_class.superclass,
                                       template_mappings)

        if ancestor_class
          error_file = template_mappings[ancestor_class]
          puts "\n\nTODO: found ancestor exception to template mapping!: '#{error_file}'"

          return error_file if File.exists?(error_file)

          log_error("Found mapping from ancestor exception class " +
                    "#{ancestor_class.name} to error file '#{error_file}', " +
                    "but error file was not found")
        end

      end # end if template_mappings

      # search for a file named after the exception in one of the search dirs

      search_paths = [ config[:error_template_dir],
                       File.join(RAILS_ROOT, 'public'),
                       File.join(JUGGLER_ROOT, 'rails', 'app', 'views', 'juggler')
                     ]

      # find files in specified directory like 'exception_class_name.format', e.g.
      # standard_error.html or standard_error.js.erb
      exception_pattern = "#{exception_filename_root}#{format_extension_pattern}"
      file_path = find_file_matching_pattern(search_paths, exception_pattern)

      puts "\n\nTODO: found exception template in search path!: '#{file_path}'" if file_path

      return file_path if file_path

      # search for a file named after the error status code in search dirs

      status_code_pattern = "#{status_code}#{format_extension_pattern}"
      file_path = find_file_matching_pattern(search_paths, status_code_pattern)

      puts "\n\nTODO: found status code template in search path!: '#{file_path}'" if file_path

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

        puts "\n\nTODO: found exception template in search path!: '#{file_path}'" if file_path

        return file_path if file_path

        curr_ancestor = curr_ancestor.superclass
      end

      # didn't find anything
      return nil
    end

  end # end ControllerMethods

end # end Juggler module
