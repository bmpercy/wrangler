# a bunch of handy exceptions. using the Http ones will require rails
module Wrangler

  # base class for all the http-related exception classes
  #-----------------------------------------------------------------------------
  class HttpStatusError < Exception
    def initialize(status_code, addl_msg = nil)
      @status_code = status_code
      @addl_msg = addl_msg

      full_message = self.class.status_to_msg(status_code)
      full_message += addl_msg unless addl_msg.nil?

      super(full_message)
    end

    attr_reader :status_code, :addl_msg

    # accepts either a Fixnum status code or a symbol representation of a
    # status code (e.g. 404 or :not_found)
    # yes, this is total duplication of code in
    # action_controller/status_codes.rb, but it's been made a private instance
    # method in the module.
    #---------------------------------------------------------------------------
    def self.status_to_msg(status)
      case status
      when Fixnum then
        "#{status} #{ActionController::StatusCodes::STATUS_CODES[status]}".strip
      when Symbol then
        status_to_msg(ActionController::StatusCodes::SYMBOL_TO_STATUS_CODE[status] ||
          "500 Unknown Status #{status.inspect}")
      else
        status.to_s
      end
    end
  end


  class HttpUnauthorized < HttpStatusError
    def initialize(msg = nil); super(401, msg); end
  end

  class HttpNotFound < HttpStatusError
    def initialize(msg = nil); super(404, msg); end
  end

  class HttpNotAcceptable < HttpStatusError
    def initialize(msg = nil); super(406, msg); end
  end

  class HttpInternalServerError < HttpStatusError
    def initialize(msg = nil); super(500, msg); end
  end

  class HttpNotImplemented < HttpStatusError
    def initialize(msg = nil); super(501, msg); end
  end
  
  class HttpServiceUnavailable < HttpStatusError
    def initialize(msg = nil); super(503, msg); end
  end

end
