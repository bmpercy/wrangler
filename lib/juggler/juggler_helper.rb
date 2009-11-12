module Juggler
  JUGGLER_ROOT = "#{File.dirname(__FILE__)}/../.."

  # make all of these instance methods act as  module functions as well
  # (any instance method below this gets added as a module function as well)
  module_function

  # utility to determine if a class has another class as its ancestor. 
  #
  # returns the ancestor class (if any) that is found to be the ancestor
  # of klass (will return the nearest ancestor in other_klasses).
  # returns nil or false otherwise.
  #
  # arguments:
  #   - klass: the class we're determining whether it has one of the other
  #            classes as an ancestor
  #   - other_klasses: a Class, an Array (or any other container that responds
  #                    to include?() ) of Classes
  #-----------------------------------------------------------------------------
  def class_has_ancestor?(klass, other_klasses)
    return nil if !klass.is_a?(Class)

    other_klasses = [other_klasses] if other_klasses.is_a?(Class)

    current_klass = klass
    while current_klass
      return current_klass if other_klasses.include?(current_klass)
      current_klass = current_klass.superclass
    end

    return false
  end


  # given an array of search directory strings (or a single directory string),
  # searches for files matching pattern.
  #
  # pattern expressed in cmd line wildcards...like "*.rb" or "foo.?"...
  # and may contain subdirectories.
  #---------------------------------------------------------------------------
  def find_file_matching_pattern(search_dirs, pattern)
    search_dirs = [search_dirs] unless search_dirs.is_a?(Array)

    search_dirs.each do |d|
      matches = Dir.glob(File.join(d, pattern))
      return matches.first if matches.size > 0
    end
    return nil
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

  # handles logging error messages, using logger if available and puts otherwise
  #-----------------------------------------------------------------------------
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

end
