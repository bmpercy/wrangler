require 'juggler/juggler_helper.rb'
require 'juggler/exception_handler.rb'
require 'juggler/exception_notifier.rb'

module Juggler

  def self.included(base)
    base.extend(ClassMethods)

    # TODO: are these useful accessor methods, or shoudl then just be 
    # accessed via the config?

    base.cattr_accessor :error_class_status_codes
    base.error_class_status_codes = Juggler::ExceptionHandler.config[:error_class_status_codes]

    base.cattr_accessor :http_status_codes
    base.http_status_codes = Juggler::ExceptionHandler.config[:http_status_codes]

   
    if class_has_ancestor?(base, ActionController::Base)
      unless Juggler::ExceptionHandler.config[:handle_public_errors]

        puts "\n\nTODO: removing rescue_action_in_public from CMs"

        ControllerMethods.send(:remove_method, :rescue_action_in_public)

        puts "TODO: is the method gone?: #{ControllerMethods.methods.include?(:rescue_action_in_public) ? 'FALSE' : 'TRUE'}"
      else
        puts "\n\nTODO: NOT removing rescue_action_in_public from CMs"
      end

      unless Juggler::ExceptionHandler.config[:handle_local_errors]
        puts "\n\nTODO: removing rescue_action_locally from CMs"

        ControllerMethods.send(:remove_method, :rescue_action_locally)
      else
        puts "\n\nTODO: NOT removing rescue_action_locally from CMs"
      end

      base.send(:include, ControllerMethods)
    end

    puts "\n\nTODO: juggler has been included into #{base.name}!\n\n"
  end

  # TODO: decide what needs to be:
  # a) class methods
  # b) instance methods (non-controller) -- kinda hope there are none of these...
  # c) controller (instance) methods (don't bother with class methods as we'll
  #    only ever interact with a controller with an instance in hand

  # methods to be class methods on the class including the Juggler module
  #-----------------------------------------------------------------------------
  module ClassMethods

    # translate the exception class to an http status code, using default
    # code (set in config) if the exception class isn't excplicitly mapped
    # to a status code in config
    #---------------------------------------------------------------------------
    def status_code_for_exception(exception)
      error_class_status_codes[exception.class] || error_class_status_codes[:default]
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

  end # end ClassMethods sub-module

  # module of instance methods to be added to the class including Juggler
  # if the including class is a rails controller class
  #-----------------------------------------------------------------------------
  module ControllerMethods

    # called by rails if the exception has already been handled (e.g. by
    # calling the rescue_from method in a controller and rendering a response)
    #---------------------------------------------------------------------------
    def rescue_with_handler(exception)
      to_return = super
      if to_return
        handle_exception(exception, request, false)
      end
      to_return
    end

    # conditionally adding these methods so that the exception handling is
    # only activated if configured to do so. these are the methods that rails
    # looks for to override default behavior
    #---------------------------------------------------------------------------
#    if Juggler::ExceptionHandler.config[:handle_public_errors]

      puts "\n\nTODO: adding in the public handler!\n\n"

      def rescue_action_in_public(exception)

        puts "\n\nTODO: rescuing in public!\n\n"

        handle_exception(exception, request, true)
      end

#    else

#      puts "\n\nTODO: NOT adding in the local handler!\n\n"


#    end
#    if Juggler::ExceptionHandler.config[:handle_local_errors]

      puts "\n\nTODO: adding in the local handler!\n\n"

      def rescue_action_locally(exception)

        puts "\n\nTODO: rescuing locally!\n\n"

        handle_exception(exception, request, true)
      end
#    else
#      puts "\n\nTODO: NOT adding in the local handler!\n\n"
#    end

    # extract a hash of relevant (and serializable) parameters from a request
    #---------------------------------------------------------------------------
    def request_data_from_request(request)
      return nil if request.nil?

      request_data = {}
      request.env.each_pair do |k,v|
        next if self.class.skip_request_env?(k)

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

    # select the proper file to render and do so
    #---------------------------------------------------------------------------
    def render_error_template(exception, status_code)
      # TODO: instead of raising exception, log error, send notification but pick
      # a default static file or template specified in config by user, and
      # if that fails, put a hardcoded path here and make sure that file is
      # in the gem

      file_path = get_view_path_for_exception(exception, status_code) or
        raise "Could not find template for exception #{exception.class} " +
        "#{exception.message}) or status code #{status_code}"

      puts "\n\nTODO: going to render error using #{file_path}"

      # TODO: try with and without layout...
      render :file => file_path,
             :status => status_code
    end

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
        if template_mappings[exception_class]
          error_file = template_mappings[exception_class]
          puts "\n\nTODO: found direct exception to template mapping!: '#{error_file}'"

          return error_file if File.exists?(error_file)

          log_error("Found mapping from exception class " +
                    "#{exception_class.name} to error file '#{error_file}', " +
                    "but error file was not found")
        end

        #---

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

      #---

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

      #---

      status_code_pattern = "#{status_code}#{format_extension_pattern}"
      file_path = find_file_matching_pattern(search_paths, status_code_pattern)

      puts "\n\nTODO: found status code template in search path!: '#{file_path}'" if file_path

      return file_path if file_path


      #---

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

    # TODO: should this be in the helper file?
    # TODO: comment
    # pattern expressed in cmd line wildcards...like "*.rb" or "foo.?"...
    #---------------------------------------------------------------------------
    def find_file_matching_pattern(search_dirs, pattern)
      search_dirs.each do |d|

        puts "TODO: trying to find #{pattern} in #{d}"

        matches = Dir.glob(File.join(d, pattern))
        return matches.first if matches.size > 0
      end
      return nil
    end

  end # end ControllerMethods

  # the main exception-handling method. decides whether to notify or not,
  # whether to render an error page or not, and to make it happen
  #-----------------------------------------------------------------------------
  def handle_exception(exception, request = nil, render_errors = false)
    status_code = self.class.status_code_for_exception(exception)
    request_data = request_data_from_request(request) unless request.nil?


    puts "\n\nTODO: status code is: #{status_code}"
#    puts "TODO: request data:"
#    puts request_data.to_yaml
#    puts "\n\n"

    if notify_on_exception?(exception, status_code)
      if notify_with_delayed_job?
        # don't pass in request as it contains not-easily-serializable stuff
        Juggler::ExceptionNotifier.send_later(:deliver_exception_notification,
                                              exception,
                                              exception.backtrace,
                                              status_code,
                                              request_data)
      else
        Juggler::ExceptionNotifier.deliver_exception_notification(exception,
                                                         exception.backtrace,
                                                         status_code,
                                                         request_data,
                                                         request)
      end
    end

    log_exception(exception, request_data, status_code)

    if render_errors

      puts "\n\nTODO: rendering error"

      render_error_template(exception, status_code)

    else
      puts "\n\nTODO: NOT rendering error"

    end
  end


  # determine if the app is configured to notify for the given exception or
  # status code
  #-----------------------------------------------------------------------------
  def notify_on_exception?(exception, status_code)
    # first determine if we're configured to notify given the context of the
    # exception
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

  # log the exception using logger if available. if object does not have a
  # logger, will just puts()
  #-----------------------------------------------------------------------------
  def log_exception(exception, request_data = nil, status_code = nil)
    msgs = []

    msgs << "An exception was caught (#{exception.class.name}):"
    msgs << exception.message
    unless request_data.blank?
      msgs <<  "Request params were:"
      msgs <<  request_data.inspect
    end
    unless status_code.blank?
      msgs <<  "Handling with status code: #{status_code}"
    end
    unless exception.backtrace.blank?
      msgs <<  exception.backtrace.join("\n  ")
    end

    log_error msgs
  end

  def log_error(msgs)
    unless msgs.is_a?(Array)
      msgs = [msgs]
    end

    msgs.each do |m|
      if respond_to?(:logger)
        logger.error m
      else
        puts m
      end
    end
  end

  # shorthand access to the exception handling config
  #-----------------------------------------------------------------------------
  def config
    Juggler::ExceptionHandler.config
  end

end # end Juggler module
