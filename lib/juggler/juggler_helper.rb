module Juggler
  JUGGLER_ROOT = "#{File.dirname(__FILE__)}/../.."

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
  def self.class_has_ancestor?(klass, other_klasses)
    return nil if !klass.is_a?(Class)

    other_klasses = [other_klasses] if other_klasses.is_a?(Class)

    current_klass = klass
    while current_klass
      return current_klass if other_klasses.include?(current_klass)
      current_klass = current_klass.superclass
    end

    return false
  end

end
